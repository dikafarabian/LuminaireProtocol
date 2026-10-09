#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS quirks — kernel 6.1
# ======================================================

SUSFS_KSU_ENABLE_VARIANTS="KSU KOWSU"

susfs_before_kernel_patch() {
    [ "${SUBLEVEL:-0}" -ge 157 ] || return 0
    log "Pre-patch: removing blk.h from namespace.c for context match (sublevel ${SUBLEVEL})..."
    sed -i '/^#include <trace\/hooks\/blk\.h>$/d' "${KERNEL_SRC}/fs/namespace.c"
}

susfs_after_kernel_patch() {
    [ "${SUBLEVEL:-0}" -ge 157 ] || return 0
    grep -qF '#include <trace/hooks/blk.h>' "${KERNEL_SRC}/fs/namespace.c" && return 0
    log "Post-patch: restoring blk.h to namespace.c..."
    sed -i '/^#include "internal\.h"$/a #include <trace\/hooks\/blk.h>' "${KERNEL_SRC}/fs/namespace.c"
    grep -qF '#include <trace/hooks/blk.h>' "${KERNEL_SRC}/fs/namespace.c" \
        || error "SuSFS: failed to restore blk.h include in namespace.c — internal.h anchor may have changed upstream!"
}
