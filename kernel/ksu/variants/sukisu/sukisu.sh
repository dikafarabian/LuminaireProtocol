#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — SukiSU-Ultra
# ======================================================
# Repo: https://github.com/SukiSU-Ultra/SukiSU-Ultra

KSU_DIR="${KERNEL_SRC}/KernelSU"

SUKISU_PRESEED_KEY=""
if susfs_active; then
    SUKISU_REF="${SUKISU_BUILTIN_REF:-builtin}"
    SUKISU_PRESEED_KEY="sukisu_builtin"
fi

ksu_integrate "SukiSU-Ultra" "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" "${SUKISU_REF:-}" "$SUKISU_PRESEED_KEY"

log "Applying Luminaire branding..."
if susfs_active; then
    BRANDING_TARGET="${KSU_DIR}/kernel/Makefile"
else
    BRANDING_TARGET="${KSU_DIR}/kernel/Kbuild"
fi
ksu_patcher branding.py "$BRANDING_TARGET" \
    || error "SukiSU-Ultra: branding patch failed!"
log "Branding applied ✅"

if susfs_active; then
    log "Patching track_throne flag compat..."
    ksu_patcher track_throne_compat.py \
        "${KSU_DIR}/kernel/manager/pkg_observer.c" \
        || error "SukiSU-Ultra: track_throne flag compat patch failed!"
    log "track_throne flag compat patched ✅"
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
ksu_publish_version
ksu_enable_configs CONFIG_KSU CONFIG_KPM

log "SukiSU-Ultra ready ✅"
