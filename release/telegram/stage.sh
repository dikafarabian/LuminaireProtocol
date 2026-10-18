#!/usr/bin/env bash

# ======================================================
# 📨 TELEGRAM — Post Staging
# ======================================================

source "${ROOT_DIR:-.}/functions.sh"

if [ "${DRY_RUN:-false}" = "true" ]; then
    log "Skipping post staging: Dry Run mode (pipeline test only)"
    return 0
fi
if [ ! -f "${ZIP_PATH:-}" ]; then
    warn "Skipping post staging: ZIP_PATH not set or file missing (ZIP_PATH='${ZIP_PATH:-}')"
    return 0
fi

VARIANT_KEY="$(variant_key)"

SUSFS_VERSION_TAG=""
if susfs_active; then
    SUSFS_VERSION_TAG="$(susfs_version_tag)"
fi

collect_versions() {
    local tokens="$1" token version_var collected=""
    for token in ${tokens//,/ }; do
        version_var="${token^^}_VERSION"
        if [ -n "${!version_var:-}" ]; then
            collected="${collected:+${collected},}${token}=${!version_var}"
        fi
    done
    echo "$collected"
}

ADDON_VERSIONS="$(collect_versions "$(feature_tokens addons)")"
PATCH_VERSIONS="$(collect_versions "${APPLIED_PATCHES:-}")"

STAGE_DIR="${GITHUB_WORKSPACE:-$PWD}/post-stage"
mkdir -p "$STAGE_DIR"
cp "$ZIP_PATH" "${STAGE_DIR}/${ZIP_NAME}"

META_FILE="$(mktemp -d)/luminaire.json"

jq -n \
    --arg variant "$VARIANT_KEY" \
    --arg variant_version "${VARIANT_VERSION_DISPLAY:-}" \
    --arg susfs_version "$SUSFS_VERSION_TAG" \
    --arg linux_ver "${KERNEL_VERSION}.${SUBLEVEL}" \
    --arg kernel_version "$KERNEL_VERSION" \
    --arg kernel_branch "${KERNEL_BRANCH:-}" \
    --arg kernel_source_owner "$KERNEL_SOURCE_OWNER" \
    --arg kernel_source_repo "$(kernel_source_repo)" \
    --arg compiler_string "${COMPILER_STRING:-}" \
    --arg lto_mode "${LTO_MODE:-}" \
    --arg addons "${ADDONS:-}" \
    --arg skipped_addons "${SKIPPED_ADDONS:-}" \
    --arg addon_versions "$ADDON_VERSIONS" \
    --arg patch_versions "$PATCH_VERSIONS" \
    --arg applied_patches "${APPLIED_PATCHES:-}" \
    --arg skipped_patches "${SKIPPED_PATCHES:-}" \
    '$ARGS.named' > "$META_FILE" \
    || error "Post staging: meta file creation failed!"

zip -q -j "${STAGE_DIR}/${ZIP_NAME}" "$META_FILE" \
    || error "Post staging: embedding meta into zip failed!"
rm -rf "$(dirname "$META_FILE")"

log "Post stage ready: ${ZIP_NAME} (${VARIANT_KEY}) ✅"

return 0
