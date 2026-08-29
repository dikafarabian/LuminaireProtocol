#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — Re:Kernel (Binder/Signal Netlink server)
# ======================================================
# Repo: https://github.com/Sakion-Team/Re-Kernel
# ======================================================

log "Integrating Re:Kernel..."

REKERNEL_PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/addons/rekernel/inject.py"
REKERNEL_HEADER="${KERNEL_SRC}/drivers/android/rekernel.h"

python3 "$REKERNEL_PATCHER" "$KERNEL_SRC" \
    || error "Re:Kernel: injection failed!"

[ -f "$REKERNEL_HEADER" ] \
    || error "Re:Kernel: rekernel.h not created!"

log "Verifying Re:Kernel hook markers in source files..."
MARKER="Re:Kernel"
for _file in \
    "${KERNEL_SRC}/drivers/android/binder.c" \
    "${KERNEL_SRC}/drivers/android/binder_alloc.c" \
    "${KERNEL_SRC}/kernel/signal.c"; do
    grep -q "$MARKER" "$_file" \
        || error "Re:Kernel: hook marker missing in ${_file##*/} — injection silently failed!"
done
log "Re:Kernel hook markers verified ✅"

grep -q "^#define REKERNEL_DEFINE_STATE$" "${KERNEL_SRC}/kernel/signal.c" \
    || error "Re:Kernel: signal.c is missing REKERNEL_DEFINE_STATE — shared state would be duplicated per translation unit!"

for _file in \
    "${KERNEL_SRC}/drivers/android/binder.c" \
    "${KERNEL_SRC}/drivers/android/binder_alloc.c"; do
    if grep -q "^#define REKERNEL_DEFINE_STATE$" "$_file"; then
        error "Re:Kernel: ${_file##*/} defines REKERNEL_DEFINE_STATE — state must be defined in exactly one translation unit!"
    fi
done
log "Re:Kernel shared state owner verified ✅"

log "Re:Kernel integrated ✅"
