#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — LZ4KD (ZRAM compression optimization)
# ======================================================
# Source: https://github.com/SukiSU-Ultra/SukiSU_patch (other/zram/)
# ======================================================

LZ4KD_RAW_BASE="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU_patch/main/other/zram"
cd "${KERNEL_SRC}"

log "Downloading LZ4KD source files..."
LZ4KD_FILES=(
    "include/linux/lz4k.h"
    "include/linux/lz4kd.h"
    "lib/lz4k/Makefile"
    "lib/lz4k/lz4k_decode.c"
    "lib/lz4k/lz4k_encode.c"
    "lib/lz4k/lz4k_encode_private.h"
    "lib/lz4k/lz4k_private.h"
    "lib/lz4kd/Makefile"
    "lib/lz4kd/lz4kd_decode.c"
    "lib/lz4kd/lz4kd_decode_delta.c"
    "lib/lz4kd/lz4kd_encode.c"
    "lib/lz4kd/lz4kd_encode_delta.c"
    "lib/lz4kd/lz4kd_encode_private.h"
    "lib/lz4kd/lz4kd_private.h"
    "crypto/lz4k.c"
    "crypto/lz4kd.c"
)
for f in "${LZ4KD_FILES[@]}"; do
    mkdir -p "$(dirname "$f")"
    fetch -o "$f" "${LZ4KD_RAW_BASE}/lz4k/${f}" \
        || error "LZ4KD: failed to download ${f}!"
done
log "LZ4KD source files staged ✅"

case "${KERNEL_VERSION}" in
    5.10|5.15|6.1|6.6) : ;;
    *) error "LZ4KD: no known SukiSU_patch zram_patch/ for kernel ${KERNEL_VERSION} yet — this addon should have been gated out before reaching here (check registry.sh's ADDON_SUPPORTED_VERSIONS)." ;;
esac

apply_remote_patch "LZ4KD" "${LZ4KD_RAW_BASE}/zram_patch/${KERNEL_VERSION}/lz4kd.patch" "$KERNEL_SRC" --fuzz=3 --no-backup-if-mismatch
gki_defconfig_enable CONFIG_CRYPTO_LZ4HC CONFIG_CRYPTO_LZ4K CONFIG_CRYPTO_LZ4KD
export LZ4KD_ENABLED=true

cd "${ROOT_DIR}"
log "LZ4KD ZRAM optimization integrated ✅"
