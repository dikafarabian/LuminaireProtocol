#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS — shared apply logic (any KSU fork, any kernel)
# ======================================================
# Repo: https://gitlab.com/simonpunk/susfs4ksu
#
# Per-kernel differences live in quirks/<kernel_version>.sh (optional):
#   SUSFS_KSU_ENABLE_VARIANTS   variants that need the 10_enable KernelSU patch
#   susfs_before_kernel_patch   runs before the kernel patch is applied
#   susfs_after_kernel_patch    runs after the kernel patch is applied
#   susfs_after_ksu_enable      runs after the 10_enable step

KSU_DIR="${KSU_DIR:-${KERNEL_SRC}/KernelSU}"
SUSFS_DIR="/tmp/susfs4ksu"
SUSFS_LOCAL_DIR="${ROOT_DIR}/kernel/ksu/susfs"

SUSFS_REF_VAR="SUSFS_${KERNEL_VARIANT}_REF"
SUSFS_REF="${!SUSFS_REF_VAR:-}"
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_BRANCH="gki-$(resolve_android_version)-${KERNEL_VERSION}"
SUSFS_MIRROR_KEY="susfs_${KERNEL_VARIANT,,}"
if [ "$KERNEL_VARIANT" = "KSUNEXT" ]; then
    SUSFS_BRANCH="${SUSFS_BRANCH}-dev"
fi
if [ "$KERNEL_VARIANT" = "SUKISU" ] && [ -z "$SUSFS_REF" ]; then
    warn "SuSFS+SukiSU: no pin resolved — build will likely fail (see wishlist for known-good combos)"
fi

SUSFS_KSU_ENABLE_VARIANTS=""
susfs_before_kernel_patch() { :; }
susfs_after_kernel_patch() { :; }
susfs_after_ksu_enable() { :; }

SUSFS_QUIRKS="${SUSFS_LOCAL_DIR}/quirks/${KERNEL_VERSION}.sh"
if [ -f "$SUSFS_QUIRKS" ]; then
    source "$SUSFS_QUIRKS"
fi

source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"
CANDIDATE_VAR="CANDIDATE_${SUSFS_MIRROR_KEY^^}"
SUSFS_MIRRORED="false"
mirror_preseed "$SUSFS_MIRROR_KEY" "$SUSFS_DIR" "$SUSFS_REF" "${!CANDIDATE_VAR:-false}" "$(resolve_android_version)-${KERNEL_VERSION}" && SUSFS_MIRRORED="true"

if [ "$SUSFS_MIRRORED" = "true" ]; then
    log "SuSFS: using pre-seeded mirror copy, skipping upstream clone"
else
    log "Cloning SuSFS (${SUSFS_BRANCH})..."
    [ -d "$SUSFS_DIR" ] && rm -rf "$SUSFS_DIR"
    git config --global http.connectTimeout 30
    git config --global http.lowSpeedLimit 1000
    git config --global http.lowSpeedTime 30
    if [ -n "${SUSFS_REF:-}" ]; then
        log "Pinning SuSFS to ${SUSFS_REF}"
        mkdir -p "$SUSFS_DIR"
        (
            cd "$SUSFS_DIR"
            git init -q
            git remote add origin "$SUSFS_REPO"
            run_quiet git fetch --depth=1 origin "$SUSFS_REF" && git checkout -q FETCH_HEAD
        ) || {
            warn "SuSFS: server doesn't support fetching bare SHA — falling back to full clone"
            rm -rf "$SUSFS_DIR"
            retry 3 run_quiet git clone -q -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
                || error "SuSFS: full clone fallback failed after 3 attempts!"
            (cd "$SUSFS_DIR" && git checkout -q "$SUSFS_REF") \
                || error "SuSFS: ${SUSFS_REF} not found on ${SUSFS_BRANCH} even after full clone!"
        }
    else
        retry 3 run_quiet git clone -q --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
            || error "SuSFS clone failed after 3 attempts!"
    fi
fi

log "Copying SuSFS source files..."
cp "${SUSFS_DIR}/kernel_patches/fs/susfs.c"                  "${KERNEL_SRC}/fs/susfs.c"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs.h"       "${KERNEL_SRC}/include/linux/susfs.h"
cp "${SUSFS_DIR}/kernel_patches/include/linux/susfs_def.h"   "${KERNEL_SRC}/include/linux/susfs_def.h"
log "SuSFS source files copied ✅"

log "Applying SuSFS kernel patch..."
KERNEL_PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-$(resolve_android_version)-${KERNEL_VERSION}.patch"
if [ ! -f "$KERNEL_PATCH" ]; then
    error "SuSFS: mandatory kernel patch not found at ${KERNEL_PATCH}"
elif patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KERNEL_PATCH" > /dev/null 2>&1; then
    log "SuSFS kernel patch already applied, skipping."
else
    susfs_before_kernel_patch

    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$KERNEL_PATCH" \
        && log "SuSFS kernel patch applied ✅" \
        || error "SuSFS: mandatory kernel patch failed (${KERNEL_PATCH}); reject files preserved in ${KERNEL_SRC}"

    susfs_after_kernel_patch
fi

if [[ " ${SUSFS_KSU_ENABLE_VARIANTS} " == *" ${KERNEL_VARIANT} "* ]]; then
    if [ "$KERNEL_VARIANT" = "KOWSU" ]; then
        KSU_PATCH="${SUSFS_LOCAL_DIR}/patches/10_enable_susfs_for_kowsu.patch"
    else
        KSU_PATCH="${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    fi
    if [ ! -f "$KSU_PATCH" ]; then
        error "SuSFS: mandatory 10_enable patch not found (${KSU_PATCH})"
    elif patch -p1 --dry-run --reverse -d "$KSU_DIR" < "$KSU_PATCH" > /dev/null 2>&1; then
        log "SuSFS: 10_enable already applied to KernelSU, skipping."
    else
        log "Applying SuSFS 10_enable KernelSU patch (${KERNEL_VARIANT})..."
        SELINUX_HIDE_C="${KSU_DIR}/kernel/feature/selinux_hide.c"
        if grep -q "sync to global sidtab" "$SELINUX_HIDE_C" 2>/dev/null; then
            log "Reverting upstream selinux_hide sidtab sync (removed by 10_enable)..."
            patch -p1 -R --forward -d "$KSU_DIR" < "${SUSFS_LOCAL_DIR}/fixes/selinux_hide_sidtab_sync.patch" \
                || error "SuSFS: selinux_hide sidtab revert failed on ${KERNEL_VARIANT}!"
        fi
        KSU_INIT_C="${KSU_DIR}/kernel/core/init.c"
        if [ "$KERNEL_VARIANT" = "KSU" ] && [ -f "$KSU_INIT_C" ]; then
            python3 "${SUSFS_LOCAL_DIR}/fixes/init_banner.py" strip "$KSU_INIT_C" \
                || error "SuSFS: init.c banner strip failed!"
        fi
        patch -p1 --fuzz=3 --forward -d "$KSU_DIR" < "$KSU_PATCH" \
            && log "SuSFS 10_enable applied ✅" \
            || error "SuSFS: mandatory 10_enable patch failed on ${KERNEL_VARIANT} (${KSU_PATCH}); reject files preserved in ${KSU_DIR}"
        if [ "$KERNEL_VARIANT" = "KSU" ] && [ -f "$KSU_INIT_C" ]; then
            python3 "${SUSFS_LOCAL_DIR}/fixes/init_banner.py" restore "$KSU_INIT_C" \
                || error "SuSFS: init.c banner restore failed!"
        fi
    fi
    susfs_after_ksu_enable
fi

rm -rf "$SUSFS_DIR"

KSU_KCONFIG="${KSU_DIR}/kernel/Kconfig"
grep -q "^config KSU_SUSFS$" "$KSU_KCONFIG" 2>/dev/null \
    || error "SuSFS: KSU_SUSFS Kconfig symbol missing in ${KERNEL_VARIANT}!"
log "KSU_SUSFS Kconfig declaration verified ✅"

log "Enabling SuSFS configs..."
if ! grep -q "^CONFIG_KSU_SUSFS=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SUS_SU=y
CONFIGS
fi
log "SuSFS configs enabled ✅"

log "SuSFS integrated ✅"
