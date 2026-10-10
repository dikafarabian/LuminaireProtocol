#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS quirks — kernel 5.15
# ======================================================

SUSFS_KSU_ENABLE_VARIANTS="KSU KOWSU"

susfs_before_kernel_patch() {
    grep -qF '#include <trace/hooks/blk.h>' "${KERNEL_SRC}/fs/namespace.c" || return 0
    log "Pre-patch: removing blk.h from namespace.c for context match..."
    sed -i '/^#include <trace\/hooks\/blk\.h>$/d' "${KERNEL_SRC}/fs/namespace.c"
    SUSFS_BLK_INCLUDE_REMOVED="true"
}

susfs_after_kernel_patch() {
    [ "${SUSFS_BLK_INCLUDE_REMOVED:-false}" = "true" ] || return 0
    log "Post-patch: restoring blk.h to namespace.c..."
    sed -i '/^#include "internal\.h"$/a #include <trace\/hooks\/blk.h>' "${KERNEL_SRC}/fs/namespace.c"
    grep -qF '#include <trace/hooks/blk.h>' "${KERNEL_SRC}/fs/namespace.c" \
        || error "SuSFS: failed to restore blk.h include in namespace.c — internal.h anchor may have changed upstream!"
}
