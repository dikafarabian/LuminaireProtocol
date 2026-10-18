#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KernelSU (official, tiann)
# ======================================================
# Repo: https://github.com/tiann/KernelSU

KSU_DIR="${KERNEL_SRC}/KernelSU"

ksu_integrate "KernelSU" "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" "${KSU_REF:-}" ksu

log "Branding skipped (official KernelSU exposes no version-tag string) ✅"

ksu_git_version "v0.9.5"
ksu_publish_version
ksu_enable_configs CONFIG_KSU

log "KernelSU ready ✅"
