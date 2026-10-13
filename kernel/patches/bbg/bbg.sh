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

cd "${ROOT_DIR}"

gki_defconfig_enable CONFIG_BBG

export BBG_ENABLED=true

log "BBG setup complete ✅ (CONFIG_LSM will be patched after defconfig)"
