#!/usr/bin/env bash

# ======================================================
# 🩹 PATCH — Workqueue (stable catch-up)
# ======================================================

WORKQUEUE_CATCHUP_PATCH="${LUMINAIRE_PATCH_DIR}/kernel/patches/workqueue_catchup/workqueue_catchup.patch"

log "🩹 Applying Workqueue stable catch-up..."
[ -f "$WORKQUEUE_CATCHUP_PATCH" ] || error "Workqueue catch-up: not backported for kernel ${KERNEL_VERSION} yet (expected ${WORKQUEUE_CATCHUP_PATCH}) — this feature should have been gated out before reaching here (check run_patches()'s support map)."

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$WORKQUEUE_CATCHUP_PATCH" > /dev/null 2>&1; then
    log "Workqueue catch-up: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$WORKQUEUE_CATCHUP_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$WORKQUEUE_CATCHUP_PATCH" \
        || error "Workqueue catch-up: patch apply failed!"
    log "Workqueue catch-up: patch applied ✅"
else
    error "Workqueue catch-up: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

log "Workqueue stable catch-up integrated ✅"
