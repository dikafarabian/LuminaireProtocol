#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — KaBI Patches
# ======================================================
# Required patches per kernel version and apply_kabi_patches

declare -A KABI_PATCHES_BY_VERSION=(
    [5.10]="sysvipc_below_6_12 posix_mqueue_5_10"
    [5.15]="sysvipc_below_6_12"
    [6.1]="sysvipc_below_6_12"
    [6.6]="sysvipc_below_6_12"
    [6.12]="sysvipc_6_12"
)

apply_kabi_patches() {
    local name patch
    [[ -v "KABI_PATCHES_BY_VERSION[${KERNEL_VERSION}]" ]] \
        || error "KaBI: kernel ${KERNEL_VERSION} is not registered in KABI_PATCHES_BY_VERSION (kernel/kabi/registry.sh)"
    for name in ${KABI_PATCHES_BY_VERSION[$KERNEL_VERSION]:-}; do
        patch="${ROOT_DIR}/kernel/kabi/${name}.patch"
        [ -f "$patch" ] || error "KaBI patch missing: ${name}.patch"
        log "Applying: $(basename "$patch")..."
        if patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
            patch -p1 --fuzz=3 -d "$KERNEL_SRC" < "$patch" || error "Patch failed: $(basename "$patch")"
            log "$(basename "$patch") applied ✅"
        elif patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
            log "$(basename "$patch") already applied, skipping."
        else
            error "$(basename "$patch") failed — conflict!"
        fi
    done
}
