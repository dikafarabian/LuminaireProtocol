#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KernelSU (official, tiann)
# ======================================================
# Repo: https://github.com/tiann/KernelSU

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LUMINAIRE_PATCH_DIR}/kernel/ksu/checkpoint/mirrors.sh"

log "Integrating KernelSU (official)..."
cd "$KERNEL_SRC"
mirror_preseed "ksu" "$KSU_DIR" "${KSU_REF:-}" "${CANDIDATE_KSU:-false}" "$(resolve_android_version)-${KERNEL_VERSION}"
KSU_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh") \
    || error "KernelSU: failed to download setup.sh!"
[ -n "$KSU_SETUP" ] || error "KernelSU: setup.sh is empty!"
echo "$KSU_SETUP" | grep -q "^#!" || error "KernelSU: setup.sh looks invalid (no shebang)!"
if [ -n "${KSU_REF:-}" ]; then
    log "Pinning KernelSU to ${KSU_REF}"
    echo "$KSU_SETUP" | bash -s -- "$KSU_REF" || error "KernelSU: setup.sh failed!"
else
    echo "$KSU_SETUP" | bash || error "KernelSU: setup.sh failed!"
fi
[ -d "$KSU_DIR" ] || error "KernelSU: KernelSU dir not found after setup!"
verify_pinned_ref "KernelSU" "$KSU_DIR" "${KSU_REF:-}"
cd "$ROOT_DIR"
log "KernelSU integrated ✅"

# Note: official KernelSU's Kbuild only exposes KSU_VERSION (numeric), no
# version-tag string to suffix — branding intentionally skipped, same as KowSU.
log "Branding skipped (official KernelSU exposes no version-tag string) ✅"

KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --tags --abbrev=0 2>/dev/null || echo "v0.9.5")
KSU_LOCAL_VERSION=$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
KSU_VERSION_CODE=$((30000 + KSU_LOCAL_VERSION))
KSU_UAPI_VERSION=$(grep -oP 'KERNEL_SU_UAPI_VERSION\s*=\s*\K[0-9]+' "${KSU_DIR}/uapi/supercall.h" 2>/dev/null || echo "")

if [ -n "$KSU_UAPI_VERSION" ]; then
    KSU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE}/${KSU_UAPI_VERSION})"
else
    KSU_VERSION_DISPLAY="${KSU_TAG_NAME} (${KSU_VERSION_CODE})"
fi
echo "KSU_VERSION_DISPLAY=${KSU_VERSION_DISPLAY}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
log "Version: ${KSU_VERSION_DISPLAY}"

log "Enabling KSU configs..."
if ! grep -q "^CONFIG_KSU=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_KSU=y
CONFIGS
fi
log "Configs enabled ✅"

log "KernelSU ready ✅"