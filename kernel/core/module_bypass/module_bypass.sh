#!/usr/bin/env bash

# ======================================================
# 🔌 CORE — Module Version Bypass
# ======================================================
# Patches kernel/module/version.c

if [ "${MODULE_BYPASS_ENABLED:-true}" != "true" ]; then
    log "Module version bypass disabled (MODULE_BYPASS_ENABLED=false) — skipping"
    return 0
fi

MODULE_VERSION_FILE="${KERNEL_SRC}/kernel/module/version.c"
PATCHER="${ROOT_DIR}/kernel/core/module_bypass/patch.py"

if [ -f "$MODULE_VERSION_FILE" ]; then
    python3 "$PATCHER" "$MODULE_VERSION_FILE" \
        || error "Module version bypass: patch script failed!"
    log "Module version bypass applied ✅"
fi
