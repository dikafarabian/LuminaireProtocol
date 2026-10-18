#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KowSU
# ======================================================
# Repo: https://github.com/KOWX712/KernelSU
# Note: KowSU's manager app (com.kowx712.supermanager) does not expose a
# separate kernel driver version field the way ReSukiSU's manager does, so
# Luminaire branding is intentionally NOT applied for this variant (cosmetic
# only, no functional impact — see project decision).

KSU_DIR="${KERNEL_SRC}/KernelSU"

ksu_integrate "KowSU" "https://raw.githubusercontent.com/KOWX712/KernelSU/main/kernel/setup.sh" "${KOWSU_REF:-}" kowsu

ksu_git_version "v0.0.1"
ksu_publish_version
ksu_enable_configs CONFIG_KSU

log "KowSU ready ✅"
