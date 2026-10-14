#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — SukiSU-Ultra
# ======================================================
# Repo: https://github.com/SukiSU-Ultra/SukiSU-Ultra

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"

log "Integrating SukiSU-Ultra..."
cd "$KERNEL_SRC"
if susfs_active; then
    mirror_preseed "sukisu_builtin" "$KSU_DIR" "${SUKISU_BUILTIN_REF:-}" "${CANDIDATE_SUKISU_BUILTIN:-false}" "$(resolve_android_version)-${KERNEL_VERSION}" || true
    SUKISU_REF="${SUKISU_BUILTIN_REF:-builtin}"
fi
run_upstream_setup "SukiSU-Ultra" "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" "${SUKISU_REF:-}"
[ -d "${KERNEL_SRC}/KernelSU" ] || error "SukiSU-Ultra: KernelSU dir not found after setup!"
verify_pinned_ref "SukiSU-Ultra" "$KSU_DIR" "${SUKISU_REF:-}"
cd "$ROOT_DIR"
log "SukiSU-Ultra integrated ✅"

log "Applying Luminaire branding..."
if susfs_active; then
    BRANDING_TARGET="${KSU_DIR}/kernel/Makefile"
else
    BRANDING_TARGET="${KSU_DIR}/kernel/Kbuild"
fi
python3 "${PATCHER_DIR}/branding.py" "$BRANDING_TARGET" \
    || error "SukiSU-Ultra: branding patch failed!"
log "Branding applied ✅"

if susfs_active; then
    log "Patching SuSFS post-execveat compat..."
    python3 "${PATCHER_DIR}/susfs_post_execveat_compat.py" \
        "${KSU_DIR}/kernel/feature/sucompat.c" \
        || error "SukiSU-Ultra: SuSFS post-execveat compat patch failed!"
    log "SuSFS post-execveat compat patched ✅"
fi

SUKISU_REPO="SukiSU-Ultra/SukiSU-Ultra"
SUKISU_VERSION_BASE=40000
SUKISU_VERSION_OFFSET=2815
SUKISU_FALLBACK_VERSION_CODE=13000

SUKISU_COMMIT_COUNT="$(github_commit_count "$SUKISU_REPO" main)"
if [ -z "$SUKISU_COMMIT_COUNT" ]; then
    SUKISU_COMMIT_COUNT="$(git -C "$KSU_DIR" rev-list --count origin/main 2>/dev/null || true)"
fi
if [ -n "$SUKISU_COMMIT_COUNT" ]; then
    KSU_VERSION_CODE=$((SUKISU_VERSION_BASE + SUKISU_COMMIT_COUNT - SUKISU_VERSION_OFFSET))
else
    KSU_VERSION_CODE=$SUKISU_FALLBACK_VERSION_CODE
fi
sed -i "s/,${SUKISU_FALLBACK_VERSION_CODE})/,${KSU_VERSION_CODE})/" "$BRANDING_TARGET"

SUKISU_RELEASE_TAG="$(github_latest_release_tag "$SUKISU_REPO" || true)"
if [ -z "$SUKISU_RELEASE_TAG" ]; then
    SUKISU_RELEASE_TAG="$(git -C "$KSU_DIR" tag --sort=-v:refname 2>/dev/null | head -n 1 || true)"
fi
KSU_TAG_NAME="v${SUKISU_RELEASE_TAG#v}"
[ "$KSU_TAG_NAME" != "v" ] || KSU_TAG_NAME="unknown"

SUKISU_MANAGER_UAPI="$(fetch "https://raw.githubusercontent.com/${SUKISU_REPO}/main/uapi/supercall.h" 2>/dev/null \
    | grep -oP 'KERNEL_SU_UAPI_VERSION\s*[=,]\s*\K[0-9]+' | head -n 1 || true)"
KSU_UAPI_VERSION="$(ksu_uapi_version "$KSU_DIR")"
if [ -z "$SUKISU_MANAGER_UAPI" ]; then
    warn "SukiSU-Ultra: couldn't read manager UAPI from main — keeping source value ${KSU_UAPI_VERSION:-unknown}"
elif [ "$KSU_UAPI_VERSION" != "$SUKISU_MANAGER_UAPI" ]; then
    sed -i -E "s/(KERNEL_SU_UAPI_VERSION[[:space:]]*[=,][[:space:]]*)[0-9]+/\1${SUKISU_MANAGER_UAPI}/" \
        "$(readlink -f "${KSU_DIR}/uapi/supercall.h")"
    log "SukiSU-Ultra: UAPI ${KSU_UAPI_VERSION:-unknown} -> ${SUKISU_MANAGER_UAPI} (aligned to manager on main)"
    KSU_UAPI_VERSION="$(ksu_uapi_version "$KSU_DIR")"
    [ "$KSU_UAPI_VERSION" = "$SUKISU_MANAGER_UAPI" ] || warn "SukiSU-Ultra: UAPI alignment did not take effect (source says ${KSU_UAPI_VERSION:-unknown})"
fi
VARIANT_VERSION_DISPLAY="$(format_ksu_version "$KSU_TAG_NAME" "$KSU_VERSION_CODE" "$KSU_UAPI_VERSION")"
github_env VARIANT_VERSION_DISPLAY "${VARIANT_VERSION_DISPLAY}"
log "Version: ${VARIANT_VERSION_DISPLAY}"

log "Enabling KSU configs..."
gki_defconfig_enable CONFIG_KSU CONFIG_KPM
log "Configs enabled ✅"

log "SukiSU-Ultra ready ✅"
