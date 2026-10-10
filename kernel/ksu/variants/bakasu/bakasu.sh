#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — BakaSU
# ======================================================
# Repo: https://github.com/Baka-SU/BakaSU

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"

log "Integrating BakaSU..."
cd "$KERNEL_SRC"
mirror_preseed "bakasu" "$KSU_DIR" "${BAKASU_REF:-}" "${CANDIDATE_BAKASU:-false}" "$(resolve_android_version)-${KERNEL_VERSION}" || true
run_upstream_setup "BakaSU" "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" "${BAKASU_REF:-}"
[ -d "${KERNEL_SRC}/KernelSU" ] || error "BakaSU: KernelSU dir not found after setup!"
verify_pinned_ref "BakaSU" "$KSU_DIR" "${BAKASU_REF:-}"
cd "$ROOT_DIR"
log "BakaSU integrated ✅"

log "Applying Luminaire branding..."
python3 "${PATCHER_DIR}/branding.py" "${KSU_DIR}/kernel/Kbuild" \
    || error "BakaSU: branding patch failed!"
log "Branding applied ✅"

KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --abbrev=0 --tags 2>/dev/null || echo "v4.1.0")
KSU_LOCAL_VERSION=$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
KSU_VERSION_CODE=$((30000 + KSU_LOCAL_VERSION + 700))
KSU_UAPI_VERSION="$(ksu_uapi_version "$KSU_DIR")"
BAKASU_VERSION_DISPLAY="$(format_ksu_version "$KSU_TAG_NAME" "$KSU_VERSION_CODE" "$KSU_UAPI_VERSION")"
github_env BAKASU_VERSION_DISPLAY "${BAKASU_VERSION_DISPLAY}"
log "Version: ${BAKASU_VERSION_DISPLAY}"

log "Patching multi-manager support..."
python3 "${PATCHER_DIR}/multimanager.py" \
    "${KSU_DIR}/kernel/manager/manager_sign.h" \
    "${KSU_DIR}/kernel/manager/apk_sign.c" \
    || error "BakaSU: multi-manager patch failed!"
log "Multi-manager patched ✅"

log "Patching KSU-Next manager compat..."
python3 "${PATCHER_DIR}/ksunext_compat.py" \
    "${KSU_DIR}/kernel/supercall/dispatch.c" \
    || error "BakaSU: KSU-Next compat patch failed!"
log "KSU-Next compat patched ✅"

log "Enabling KSU configs..."
gki_defconfig_enable CONFIG_KSU CONFIG_KPM
log "Configs enabled ✅"

log "BakaSU ready ✅"
