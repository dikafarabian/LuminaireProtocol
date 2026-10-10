#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — Addons
# ======================================================
# Supported kernel versions, order, conflict rules and run_addons

declare -A ADDON_SUPPORTED_VERSIONS=(
    [nomount]="5.10 5.15 6.1 6.6 6.12"
    [droidspaces]="5.10 5.15 6.1 6.6 6.12"
    [rekernel]="5.10 5.15 6.1 6.6 6.12"
    [ntsync]="5.10 5.15 6.1 6.6"
    [lz4zstd]="6.1 6.6"
    [lz4kd]="5.10 5.15 6.1 6.6"
    [mglru]="6.1 6.6 6.12"
)

ADDON_ORDER=(nomount droidspaces rekernel ntsync lz4zstd lz4kd mglru)

ADDON_MOUNTLESS_TOKENS=(nomount)

addon_supports_kernel_version() {
    local addon="$1"
    local supported="${ADDON_SUPPORTED_VERSIONS[$addon]:-}"
    [ -z "$supported" ] && return 1
    [[ " ${supported} " == *" ${KERNEL_VERSION} "* ]]
}

addon_skip() {
    warn "$1"
    ADDON_SKIPPED=true
}

run_addons() {
    local ordered=("${ADDON_ORDER[@]}") addon selected script order_csv mountless_csv
    order_csv="$(join_csv "${ADDON_ORDER[@]}")"
    mountless_csv="$(join_csv "${ADDON_MOUNTLESS_TOKENS[@]}")"
    unset ADDON_ORDER ADDON_MOUNTLESS_TOKENS
    export ADDON_ORDER="$order_csv" ADDON_MOUNTLESS_TOKENS="$mountless_csv"
    github_env ADDON_ORDER "$order_csv"
    github_env ADDON_MOUNTLESS_TOKENS "$mountless_csv"

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
        if ! addon_supports_kernel_version "$addon"; then
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
        [[ ",${order_csv}," == *",${selected},"* ]] || warn "Addon '${selected}' is not listed in ADDON_ORDER (kernel/addons/registry.sh) — ignored."
    done

    github_env APPLIED_ADDONS "$APPLIED_ADDONS"
    github_env SKIPPED_ADDONS "$SKIPPED_ADDONS"
    echo "::endgroup::"
}
