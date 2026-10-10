#!/usr/bin/env bash

# ======================================================
# 📦 PATCH — BBG (Baseband Guard LSM)
# ======================================================
# Repo: https://github.com/vc-teahouse/Baseband-guard

log "Setting up Baseband Guard (BBG)..."
cd "${KERNEL_SRC}"
run_upstream_setup "BBG" "https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh"
[ -L "${KERNEL_SRC}/security/baseband-guard" ] \
    || error "BBG: inject failed — security/baseband-guard symlink not found!"

PATCHER="${ROOT_DIR}/kernel/patches/bbg/kconfig_inject.py"
python3 "$PATCHER" "${KERNEL_SRC}/security/Kconfig" \
    || error "BBG: Kconfig inject failed!"

cd "${ROOT_DIR}"

gki_defconfig_enable CONFIG_BBG

export BBG_ENABLED=true

log "BBG setup complete ✅ (CONFIG_LSM will be patched after defconfig)"
