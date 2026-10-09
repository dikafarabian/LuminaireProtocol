#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS quirks — kernel 6.6
# ======================================================

SUSFS_KSU_ENABLE_VARIANTS="KSU KOWSU"

susfs_after_ksu_enable() {
    grep -q 'Wno-pointer-bool-conversion' "${KSU_DIR}/kernel/Kbuild" \
        || printf 'ccflags-y += -Wno-pointer-bool-conversion\n' >> "${KSU_DIR}/kernel/Kbuild"
}
