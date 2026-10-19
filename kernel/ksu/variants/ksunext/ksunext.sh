#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KernelSU-Next
# ======================================================
# Repo: https://github.com/pershoot/KernelSU-Next (dev-susfs)

KSU_DIR="${KERNEL_SRC}/KernelSU-Next"

KSUNEXT_REPO_URL="https://github.com/pershoot/KernelSU-Next"
KSUNEXT_SETUP_URL="https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh"

ksu_integrate "KernelSU-Next" "$KSUNEXT_SETUP_URL" "${KSUNEXT_REF:-dev-susfs}" ksunext

git -C "$KSU_DIR" fetch --force "$KSUNEXT_REPO_URL" "refs/heads/dev:refs/remotes/origin/dev" 2>/dev/null || true
[ -f "$KSU_DIR/.git/shallow" ] && git -C "$KSU_DIR" fetch --unshallow 2>/dev/null || true

log "Applying Luminaire branding..."
ksu_patcher branding.py "${KSU_DIR}/kernel/Kbuild" \
    || error "KernelSU-Next: branding patch failed!"
log "Branding applied ✅"

KSUNEXT_CUR_BRANCH=$(git -C "$KSU_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
KSUNEXT_BASE_BRANCH="${KSUNEXT_CUR_BRANCH%%-*}"
KSUNEXT_BASE_COMMIT=$(git -C "$KSU_DIR" merge-base HEAD "refs/remotes/origin/${KSUNEXT_BASE_BRANCH}" 2>/dev/null \
    || git -C "$KSU_DIR" merge-base HEAD refs/remotes/origin/main 2>/dev/null \
    || echo HEAD)

ksu_git_version "v0.0.1" 0 "$KSUNEXT_BASE_COMMIT"
ksu_publish_version
ksu_enable_configs CONFIG_KSU

log "KernelSU-Next ready ✅"
