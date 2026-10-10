#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — MGLRU (force-enable)
# ======================================================

VMSCAN_C="${KERNEL_SRC}/mm/vmscan.c"
PATCHER="${ROOT_DIR}/kernel/addons/mglru/patch.py"

[ -f "$VMSCAN_C" ] || { addon_skip "mm/vmscan.c not found, skipping mglru"; return 0; }

grep -q "^static ssize_t store_enabled(struct kobject \*kobj," "$VMSCAN_C" \
    || { addon_skip "store_enabled() not found in this kernel's shape — MGLRU doesn't exist here or its shape changed, skipping"; return 0; }

python3 "$PATCHER" "$VMSCAN_C" \
    || error "mglru: patch script failed!"

log "mglru force-enable applied ✅"
