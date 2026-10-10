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
    export APPLIED_PATCHES="" SKIPPED_PATCHES=""
    local _tfo_csv
    IFS=, ; _tfo_csv="${PATCH_FEATURE_ORDER[*]}"; unset IFS
    echo "PATCH_FEATURE_ORDER=${_tfo_csv}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    for feature in "${PATCH_FEATURE_ORDER[@]}"; do
        local supported="${PATCH_SUPPORTED_VERSIONS[$feature]:-}"
        if [[ " ${supported} " != *" ${KERNEL_VERSION} "* ]]; then
            warn "Patch feature '${feature}' isn't backported for kernel ${KERNEL_VERSION} yet — skipping (always-on, not a user toggle; shows as N/A in the release caption, not a Disable)."
            SKIPPED_PATCHES="${SKIPPED_PATCHES:+${SKIPPED_PATCHES},}${feature}"
            continue
        fi
        local script="${ROOT_DIR}/kernel/patches/${feature}/${feature}.sh"
        [ -f "$script" ] || error "Patch feature '${feature}' is marked supported for kernel ${KERNEL_VERSION} in PATCH_SUPPORTED_VERSIONS but ${script} doesn't exist — the map is out of sync with kernel/patches/."
        source "$script"
        APPLIED_PATCHES="${APPLIED_PATCHES:+${APPLIED_PATCHES},}${feature}"
    done

    unset PATCH_FEATURE_ORDER
    export PATCH_FEATURE_ORDER="${_tfo_csv}"
    echo "APPLIED_PATCHES=${APPLIED_PATCHES}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "SKIPPED_PATCHES=${SKIPPED_PATCHES}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"
}
