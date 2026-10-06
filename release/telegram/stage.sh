#!/usr/bin/env bash

# ======================================================
# 📨 TELEGRAM — Post Staging
# ======================================================

source "${LUMINAIRE_PATCH_DIR:-.}/functions.sh"

if [ "${DRY_RUN:-false}" = "true" ]; then
    log "Skipping post staging: Dry Run mode (pipeline test only)"
    return 0
fi
if [ ! -f "${ZIP_PATH:-}" ]; then
    warn "Skipping post staging: ZIP_PATH not set or file missing (ZIP_PATH='${ZIP_PATH:-}')"
    return 0
fi

case "${KERNEL_VARIANT}" in
    KSU)      KERNEL_VARIANT_VERSION="${KSU_VERSION_DISPLAY:-}" ;;
    KOWSU)    KERNEL_VARIANT_VERSION="${KOWSU_VERSION_DISPLAY:-}" ;;
    KSUNEXT)  KERNEL_VARIANT_VERSION="${KSUNEXT_VERSION_DISPLAY:-}" ;;
    SUKISU)   KERNEL_VARIANT_VERSION="${SUKISU_VERSION_DISPLAY:-}" ;;
    BAKASU) KERNEL_VARIANT_VERSION="${BAKASU_VERSION_DISPLAY:-}" ;;
    *)        KERNEL_VARIANT_VERSION="" ;;
esac

VARIANT_KEY="${KERNEL_VARIANT}"
if [ "${SUSFS_ENABLED:-false}" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ]; then
    VARIANT_KEY="${KERNEL_VARIANT}_SUSFS"
fi

SUSFS_VERSION_TAG=""
if [ "${SUSFS_ENABLED:-false}" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ]; then
    SUSFS_VERSION_TAG="$(sed -n 's/^#define SUSFS_VERSION "\(.*\)"/\1/p' "${KERNEL_SRC:-}/include/linux/susfs.h" 2>/dev/null | head -n 1)" || true
fi

STAGE_DIR="${GITHUB_WORKSPACE:-$PWD}/post-stage"
mkdir -p "$STAGE_DIR"
cp "$ZIP_PATH" "${STAGE_DIR}/${ZIP_NAME}"

META_FILE="$(mktemp -d)/luminaire.json"

jq -n \
    --arg variant "$VARIANT_KEY" \
    --arg variant_version "$KERNEL_VARIANT_VERSION" \
    --arg susfs_version "$SUSFS_VERSION_TAG" \
    --arg linux_ver "${KERNEL_VERSION}.${SUBLEVEL}" \
    --arg kernel_version "$KERNEL_VERSION" \
    --arg kernel_branch "${KERNEL_BRANCH:-}" \
    --arg compiler_string "${COMPILER_STRING:-}" \
    --arg lto_mode "${LTO_MODE:-}" \
    --arg addons "${ADDONS:-}" \
    --arg addon_order "${ADDON_ORDER:-}" \
    --arg skipped_addons "${SKIPPED_ADDONS:-}" \
    --arg applied_tuning "${APPLIED_TUNING:-}" \
    --arg skipped_tuning "${SKIPPED_TUNING:-}" \
    '$ARGS.named' > "$META_FILE" \
    || error "Post staging: meta file creation failed!"

zip -q -j "${STAGE_DIR}/${ZIP_NAME}" "$META_FILE" \
    || error "Post staging: embedding meta into zip failed!"
rm -rf "$(dirname "$META_FILE")"

log "Post stage ready: ${ZIP_NAME} (${VARIANT_KEY}) ✅"

return 0
