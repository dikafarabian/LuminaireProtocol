#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — Core
# ======================================================
# Core features come from kernel/features.json

run_core() {
    echo "::group::🔧 Core"
    local feature script
    local -a features
    mapfile -t features < <(feature_tokens core)
    for feature in "${features[@]}"; do
        script="${ROOT_DIR}/kernel/core/${feature}/${feature}.sh"
        [ -f "$script" ] || error "Core feature '${feature}' is listed in kernel/features.json but ${script} doesn't exist."
        source "$script"
    done
    echo "::endgroup::"
}
