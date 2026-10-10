#!/usr/bin/env bash

# ======================================================
# ⚙️ PATCH — Kcompressd
# ======================================================

KCOMPRESSD_PATCH="${ROOT_DIR}/kernel/patches/kcompressd/kcompressd-v0.5.patch"

log "⚙️ Applying Kcompressd patch..."
apply_patch "kcompressd" "$KCOMPRESSD_PATCH" "$KERNEL_SRC" --fuzz=3

KCOMPRESSD_VERSION="$(basename "$KCOMPRESSD_PATCH" .patch | sed 's/^kcompressd-//')"
github_env KCOMPRESSD_VERSION "$KCOMPRESSD_VERSION"

log "Kcompressd integrated ✅"
