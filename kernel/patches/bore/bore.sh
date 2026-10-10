#!/usr/bin/env bash

# ======================================================
# 🔥 PATCH — BORE (CPU scheduler)
# ======================================================

BORE_PATCH="${ROOT_DIR}/kernel/patches/bore/bore-v6.8.0-rc1.patch"

log "🔥 Applying BORE CPU scheduler patch..."
apply_patch "BORE" "$BORE_PATCH" "$KERNEL_SRC" --fuzz=3
gki_defconfig_enable CONFIG_SCHED_BORE

BORE_VERSION="$(basename "$BORE_PATCH" .patch | sed 's/^bore-//')"
github_env BORE_VERSION "$BORE_VERSION"

log "BORE CPU scheduler integrated ✅"
