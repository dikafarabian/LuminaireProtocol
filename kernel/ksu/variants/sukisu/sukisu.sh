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
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    mirror_preseed "sukisu_builtin" "$KSU_DIR" "${SUKISU_BUILTIN_REF:-}" "${CANDIDATE_SUKISU_BUILTIN:-false}" "$(resolve_android_version)-${KERNEL_VERSION}" || true
    SUKISU_REF="${SUKISU_BUILTIN_REF:-builtin}"
fi
run_upstream_setup "SukiSU-Ultra" "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" "${SUKISU_REF:-}"
[ -d "${KERNEL_SRC}/KernelSU" ] || error "SukiSU-Ultra: KernelSU dir not found after setup!"
verify_pinned_ref "SukiSU-Ultra" "$KSU_DIR" "${SUKISU_REF:-}"
cd "$ROOT_DIR"
log "SukiSU-Ultra integrated ✅"

log "Applying Luminaire branding..."
if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
    BRANDING_TARGET="${KSU_DIR}/kernel/Makefile"
else
    BRANDING_TARGET="${KSU_DIR}/kernel/Kbuild"
fi
python3 "${PATCHER_DIR}/branding.py" "$BRANDING_TARGET" \
    || error "SukiSU-Ultra: branding patch failed!"
log "Branding applied ✅"

if [ "${SUSFS_ENABLED:-false}" = "true" ]; then
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

SUKISU_RELEASE_TAG="$(github_latest_release_tag "$SUKISU_REPO" || true)"
if [ -z "$SUKISU_RELEASE_TAG" ]; then
    SUKISU_RELEASE_TAG="$(git -C "$KSU_DIR" tag --sort=-v:refname 2>/dev/null | head -n 1 || true)"
fi
KSU_TAG_NAME="v${SUKISU_RELEASE_TAG#v}"
[ "$KSU_TAG_NAME" != "v" ] || KSU_TAG_NAME="unknown"

KSU_UAPI_VERSION="$(ksu_uapi_version "$KSU_DIR")"
SUKISU_VERSION_DISPLAY="$(format_ksu_version "$KSU_TAG_NAME" "$KSU_VERSION_CODE" "$KSU_UAPI_VERSION")"
github_env SUKISU_VERSION_DISPLAY "${SUKISU_VERSION_DISPLAY}"
log "Version: ${SUKISU_VERSION_DISPLAY}"

log "Enabling KSU configs..."
gki_defconfig_enable CONFIG_KSU CONFIG_KPM
log "Configs enabled ✅"

log "SukiSU-Ultra ready ✅"
