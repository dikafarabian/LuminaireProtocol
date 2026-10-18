#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — BakaSU
# ======================================================
# Repo: https://github.com/Baka-SU/BakaSU

KSU_DIR="${KERNEL_SRC}/KernelSU"

ksu_integrate "BakaSU" "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" "${BAKASU_REF:-}" bakasu

log "Applying Luminaire branding..."
ksu_patcher branding.py "${KSU_DIR}/kernel/Kbuild" \
    || error "BakaSU: branding patch failed!"
log "Branding applied ✅"

ksu_git_version "v4.1.0" 700
ksu_publish_version

log "Patching multi-manager support..."
ksu_patcher multimanager.py \
    "${KSU_DIR}/kernel/manager/manager_sign.h" \
    "${KSU_DIR}/kernel/manager/apk_sign.c" \
    || error "BakaSU: multi-manager patch failed!"
log "Multi-manager patched ✅"

log "Patching KSU-Next manager compat..."
ksu_patcher ksunext_compat.py \
    "${KSU_DIR}/kernel/supercall/dispatch.c" \
    || error "BakaSU: KSU-Next compat patch failed!"
log "KSU-Next compat patched ✅"

ksu_enable_configs CONFIG_KSU CONFIG_KPM

log "BakaSU ready ✅"
