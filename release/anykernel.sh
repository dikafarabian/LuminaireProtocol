#!/usr/bin/env bash

# ======================================================
# 📦 RELEASE — AnyKernel3 Packaging
# ======================================================
# Repo: https://github.com/chainonyourdoor/AnyKernel3-Luminaire

[ -n "${SUBLEVEL:-}" ] || error "SUBLEVEL is not set — branding.sh may not have run correctly!"
ZIP_NAME="Ak3-${KERNEL_VERSION}.${SUBLEVEL}-$(variant_label)-R${GITHUB_RUN_NUMBER:-0}.zip"
export ZIP_NAME

if [ "${USE_AK3_CACHE}" = "true" ] && [ -d "${HOME}/ak3-cache" ]; then
    cp -a "${HOME}/ak3-cache/." "${TOOL_AK3_DIR}/"
    log "AnyKernel3 restored from cache ✅ ($(cache_freshness_note))"
else
    retry 3 run_quiet git clone -q --depth=1 \
        https://github.com/chainonyourdoor/AnyKernel3-Luminaire.git "$TOOL_AK3_DIR" \
        || error "Failed to clone AK3! (see output above)"
    mkdir -p "${HOME}/ak3-cache"
    cp -a "${TOOL_AK3_DIR}/." "${HOME}/ak3-cache/"
fi

[ -d "$TOOL_AK3_DIR" ] || error "AK3 directory missing after clone/cache restore — aborting packaging"

KERNEL_IMG=""
if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
    BOOT_SEARCH_DIR="$KLEAF_OUT_DIR"
else
    BOOT_SEARCH_DIR="${OUT_DIR}/arch/${ARCH}/boot"
fi

for img in Image Image.gz Image.gz-dtb Image-dtb; do
    BOOT_PATH="${BOOT_SEARCH_DIR}/${img}"
    if [ -f "$BOOT_PATH" ]; then
        KERNEL_IMG="$BOOT_PATH"
        log "Kernel image: $img (from ${BUILD_SYSTEM})"
        break
    fi
done
[ -n "$KERNEL_IMG" ] || error "Kernel image not found! Searched ${BOOT_SEARCH_DIR}/ for: Image, Image.gz, Image.gz-dtb, Image-dtb"

cp "$KERNEL_IMG" "${TOOL_AK3_DIR}/"

ZRAM_KO="${OUT_DIR}/drivers/block/zram/zram.ko"
if [ -f "$ZRAM_KO" ]; then
    mkdir -p "${TOOL_AK3_DIR}/modules"
    cp "$ZRAM_KO" "${TOOL_AK3_DIR}/modules/"
    log "LZ4KD: zram.ko included in zip under modules/ (manual insmod required, see release notes) ✅"
fi

ZIP_PATH="/tmp/${ZIP_NAME}"
export ZIP_PATH ZIP_NAME
cd "$TOOL_AK3_DIR"
zip -r9 "$ZIP_PATH" . -x "*.git*" -x "*.github*" -x "*.md" -x "LICENSE" \
    || error "ZIP creation failed!"
[ -f "$ZIP_PATH" ] || error "ZIP file not found after creation!"
cd "$ROOT_DIR"

log "ZIP ready: ${ZIP_NAME} ✅"
