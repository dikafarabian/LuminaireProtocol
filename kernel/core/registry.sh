#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — Core
# ======================================================
# Core feature order and run_core

CORE_FEATURE_ORDER=(dirty_flag glibc protected_exports compiler_string module_bypass openssl3_compat)

run_core() {
    echo "::group::🔧 Core"
    local feature script
    for feature in "${CORE_FEATURE_ORDER[@]}"; do
        script="${ROOT_DIR}/kernel/core/${feature}/${feature}.sh"
        [ -f "$script" ] || error "Core feature '${feature}' is listed in CORE_FEATURE_ORDER but ${script} doesn't exist — the list is out of sync with kernel/core/."
        source "$script" || error "Core feature failed: ${feature}"
    done
    echo "::endgroup::"
}
