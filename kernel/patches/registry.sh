#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — Patches
# ======================================================
# Supported kernel versions, order and run_patches come from kernel/features.json

run_patches() {
    echo "::group::✨ Patches"
    local feature script
    local -a features
    mapfile -t features < <(feature_tokens patches)
    export APPLIED_PATCHES="" SKIPPED_PATCHES=""
    for feature in "${features[@]}"; do
        if ! feature_supports_kernel_version patches "$feature"; then
            warn "Patch feature '${feature}' isn't backported for kernel ${KERNEL_VERSION} yet — skipping (always-on, not a user toggle; shows as N/A in the release caption, not a Disable)."
            SKIPPED_PATCHES="${SKIPPED_PATCHES:+${SKIPPED_PATCHES},}${feature}"
            continue
        fi
        script="${ROOT_DIR}/kernel/patches/${feature}/${feature}.sh"
        [ -f "$script" ] || error "Patch feature '${feature}' is marked supported for kernel ${KERNEL_VERSION} in kernel/features.json but ${script} doesn't exist."
        source "$script"
        APPLIED_PATCHES="${APPLIED_PATCHES:+${APPLIED_PATCHES},}${feature}"
    done
    echo "::endgroup::"
}
