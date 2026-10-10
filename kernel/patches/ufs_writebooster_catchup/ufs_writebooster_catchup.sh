#!/usr/bin/env bash

# ======================================================
# 🩹 PATCH — UFS / WriteBooster (stable catch-up)
# ======================================================

UFS_WRITEBOOSTER_CATCHUP_PATCH="${ROOT_DIR}/kernel/patches/ufs_writebooster_catchup/ufs_writebooster_catchup.patch"

log "🩹 Applying UFS / WriteBooster stable catch-up..."
apply_patch "UFS/WriteBooster catch-up" "$UFS_WRITEBOOSTER_CATCHUP_PATCH" "$KERNEL_SRC" --fuzz=3

log "UFS / WriteBooster stable catch-up integrated ✅"
