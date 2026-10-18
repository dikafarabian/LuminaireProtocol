#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — Addons
# ======================================================
# Supported kernel versions, order and run_addons come from kernel/features.json

addon_skip() {
    warn "$1"
    ADDON_SKIPPED=true
}

run_addons() {
    local addon selected script
    local -a ordered
    mapfile -t ordered < <(feature_tokens addons)

    ADDONS="${ADDONS:-}"
    ADDONS="${ADDONS// /}"
    ADDONS="$(sed 's/^,*//;s/,*$//;s/,,*/,/g' <<< "$ADDONS")"
    [ -n "$ADDONS" ] || return 0
    echo "::group::⚡ Addons"

    export APPLIED_ADDONS="" SKIPPED_ADDONS=""

    for addon in "${ordered[@]}"; do
        [[ ",${ADDONS}," == *",${addon},"* ]] || continue
        script="${ROOT_DIR}/kernel/addons/${addon}/${addon}.sh"
        if [ ! -f "$script" ]; then
            log "⚠️ Addon not found: ${addon}"
            continue
        fi
        if ! feature_supports_kernel_version addons "$addon"; then
            warn "Addon '${addon}' isn't backported for kernel ${KERNEL_VERSION} yet — skipping (shows as N/A, not Disable, in the release caption)."
            SKIPPED_ADDONS="${SKIPPED_ADDONS:+${SKIPPED_ADDONS},}${addon}"
            continue
        fi
        ADDON_SKIPPED=false
        source "$script"
        if [ "$ADDON_SKIPPED" = "true" ]; then
            SKIPPED_ADDONS="${SKIPPED_ADDONS:+${SKIPPED_ADDONS},}${addon}"
        else
            APPLIED_ADDONS="${APPLIED_ADDONS:+${APPLIED_ADDONS},}${addon}"
        fi
    done

    IFS=',' read -ra ADDON_LIST <<< "$ADDONS"
    for selected in "${ADDON_LIST[@]}"; do
        [[ " ${ordered[*]} " == *" ${selected} "* ]] || warn "Addon '${selected}' is not listed in kernel/features.json — ignored."
    done

    echo "::endgroup::"
}
