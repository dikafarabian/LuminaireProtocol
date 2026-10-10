#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — Patches
# ======================================================
# Supported kernel versions, order and run_patches

declare -A PATCH_SUPPORTED_VERSIONS=(
    [bore]="6.1"
    [le9uo]="6.1"
    [kcompressd]="6.1"
    [workqueue_catchup]="6.1"
    [schedutil_catchup]="6.1"
    [ufs_writebooster_catchup]="6.1"
    [bbrv3]="5.10 5.15 6.1 6.6"
    [bbg]="5.10 5.15 6.1 6.6 6.12"
    [wireguard]="5.10 5.15 6.1 6.6 6.12"
)

PATCH_FEATURE_ORDER=(bore bbrv3 bbg wireguard le9uo kcompressd workqueue_catchup schedutil_catchup ufs_writebooster_catchup)

run_patches() {
    echo "::group::✨ Patches"
    local feature supported script order_csv
    order_csv="$(join_csv "${PATCH_FEATURE_ORDER[@]}")"
    export APPLIED_PATCHES="" SKIPPED_PATCHES=""
    github_env PATCH_FEATURE_ORDER "$order_csv"
    for feature in "${PATCH_FEATURE_ORDER[@]}"; do
        supported="${PATCH_SUPPORTED_VERSIONS[$feature]:-}"
        if [[ " ${supported} " != *" ${KERNEL_VERSION} "* ]]; then
            warn "Patch feature '${feature}' isn't backported for kernel ${KERNEL_VERSION} yet — skipping (always-on, not a user toggle; shows as N/A in the release caption, not a Disable)."
            SKIPPED_PATCHES="${SKIPPED_PATCHES:+${SKIPPED_PATCHES},}${feature}"
            continue
        fi
        script="${ROOT_DIR}/kernel/patches/${feature}/${feature}.sh"
        [ -f "$script" ] || error "Patch feature '${feature}' is marked supported for kernel ${KERNEL_VERSION} in PATCH_SUPPORTED_VERSIONS but ${script} doesn't exist — the map is out of sync with kernel/patches/."
        source "$script"
        APPLIED_PATCHES="${APPLIED_PATCHES:+${APPLIED_PATCHES},}${feature}"
    done

    unset PATCH_FEATURE_ORDER
    export PATCH_FEATURE_ORDER="$order_csv"
    github_env APPLIED_PATCHES "$APPLIED_PATCHES"
    github_env SKIPPED_PATCHES "$SKIPPED_PATCHES"
    echo "::endgroup::"
}
