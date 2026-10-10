#!/usr/bin/env bash

# ======================================================
# 🩹 PATCH — Workqueue (stable catch-up)
# ======================================================

WORKQUEUE_CATCHUP_PATCH="${ROOT_DIR}/kernel/patches/workqueue_catchup/workqueue_catchup.patch"

log "🩹 Applying Workqueue stable catch-up..."
apply_patch "Workqueue catch-up" "$WORKQUEUE_CATCHUP_PATCH" "$KERNEL_SRC" --fuzz=3

log "Workqueue stable catch-up integrated ✅"
