#!/usr/bin/env bash

# ======================================================
# 🩹 PATCH — Schedutil (stable catch-up)
# ======================================================

SCHEDUTIL_CATCHUP_PATCH="${ROOT_DIR}/kernel/patches/schedutil_catchup/schedutil_catchup.patch"

log "🩹 Applying Schedutil stable catch-up..."
apply_patch "Schedutil catch-up" "$SCHEDUTIL_CATCHUP_PATCH" "$KERNEL_SRC" --fuzz=3

log "Schedutil stable catch-up integrated ✅"
