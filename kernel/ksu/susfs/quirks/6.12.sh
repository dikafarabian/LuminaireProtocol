#!/usr/bin/env bash

# ======================================================
# 🧬 SuSFS quirks — kernel 6.12
# ======================================================

susfs_extra_fixes() {
    log "Fixing task_mmu.c SUS_MAP guard placement (safety fallback for vma_pages/vma_data_pages rename)..."
    python3 "${SUSFS_LOCAL_DIR}/fixes/fix_task_mmu_sus_map.py" "${KERNEL_SRC}/fs/proc/task_mmu.c" \
        || error "SuSFS: task_mmu.c SUS_MAP fix failed!"
    log "task_mmu.c fixed ✅"
}
