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
mirror_preseed "bakasu" "$KSU_DIR" "${BAKASU_REF:-}" "${CANDIDATE_BAKASU:-false}" "$(resolve_android_version)-${KERNEL_VERSION}"
BAKASU_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh") \
    || error "BakaSU: failed to download setup.sh!"
[ -n "$BAKASU_SETUP" ] || error "BakaSU: setup.sh is empty!"
echo "$BAKASU_SETUP" | grep -q "^#!" || error "BakaSU: setup.sh looks invalid (no shebang)!"
if [ -n "${BAKASU_REF:-}" ]; then
    log "Pinning BakaSU to ${BAKASU_REF}"
    echo "$BAKASU_SETUP" | bash -s -- "$BAKASU_REF" || error "BakaSU: setup.sh failed!"
else
    echo "$BAKASU_SETUP" | bash || error "BakaSU: setup.sh failed!"
fi
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
KSU_UAPI_VERSION=$(grep -oP 'KERNEL_SU_UAPI_VERSION\s*=\s*\K[0-9]+' "${KSU_DIR}/uapi/supercall.h" 2>/dev/null || echo "")

if [ -n "$KSU_UAPI_VERSION" ]; then
    BAKASU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE}/${KSU_UAPI_VERSION})"
else
    BAKASU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE})"
fi
echo "BAKASU_VERSION_DISPLAY=${BAKASU_VERSION_DISPLAY}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
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
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIG_KPM=y
CONFIGS
fi
log "Configs enabled ✅"

log "BakaSU ready ✅"
