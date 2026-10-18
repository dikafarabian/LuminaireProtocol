#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — KaBI Patches
# ======================================================
# Required patches per kernel version come from kernel/features.json

apply_kabi_patches() {
    local name patch
    local -a names
    jq -e --arg version "$KERNEL_VERSION" '.versions[$version].kabi' "$FEATURES_FILE" > /dev/null \
        || error "KaBI: kernel ${KERNEL_VERSION} has no kabi entry in kernel/features.json"
    mapfile -t names < <(jq -r --arg version "$KERNEL_VERSION" '.versions[$version].kabi[]' "$FEATURES_FILE")
    for name in "${names[@]}"; do
        patch="${ROOT_DIR}/kernel/kabi/${name}.patch"
        [ -f "$patch" ] || error "KaBI patch missing: ${name}.patch"
        log "Applying: $(basename "$patch")..."
        if patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
            patch -p1 --fuzz=3 --no-backup-if-mismatch -d "$KERNEL_SRC" < "$patch" || error "Patch failed: $(basename "$patch")"
            log "$(basename "$patch") applied ✅"
        elif patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$patch" > /dev/null 2>&1; then
            log "$(basename "$patch") already applied, skipping."
        else
            error "$(basename "$patch") failed — conflict!"
        fi
    done
}
