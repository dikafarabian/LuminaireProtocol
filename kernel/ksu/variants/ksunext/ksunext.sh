#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KernelSU-Next
# ======================================================
# Repo: https://github.com/KernelSU-Next/KernelSU-Next

KSU_DIR="${KERNEL_SRC}/KernelSU-Next"

if susfs_active; then
    log "SUSFS enabled — using pershoot/KernelSU-Next's dev-susfs fork"
    KSUNEXT_REPO_URL="https://github.com/pershoot/KernelSU-Next"
    KSUNEXT_SETUP_URL="https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh"
    KSUNEXT_SETUP_REF="${KSUNEXT_SUSFS_FORK_REF:-dev-susfs}"
    KSUNEXT_PRESEED_KEY="ksunext_susfs_fork"
else
    KSUNEXT_REPO_URL="https://github.com/KernelSU-Next/KernelSU-Next"
    KSUNEXT_SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh"
    KSUNEXT_SETUP_REF="${KSUNEXT_REF:-}"
    KSUNEXT_PRESEED_KEY=""
fi

ksu_integrate "KernelSU-Next" "$KSUNEXT_SETUP_URL" "$KSUNEXT_SETUP_REF" "$KSUNEXT_PRESEED_KEY"

git -C "$KSU_DIR" fetch --force "$KSUNEXT_REPO_URL" "refs/heads/dev:refs/remotes/origin/dev" 2>/dev/null || true
[ -f "$KSU_DIR/.git/shallow" ] && git -C "$KSU_DIR" fetch --unshallow 2>/dev/null || true

log "Applying Luminaire branding..."
ksu_patcher branding.py "${KSU_DIR}/kernel/Kbuild" \
    || error "KernelSU-Next: branding patch failed!"
log "Branding applied ✅"

if susfs_active; then
    KSUNEXT_CUR_BRANCH=$(git -C "$KSU_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    KSUNEXT_BASE_BRANCH="${KSUNEXT_CUR_BRANCH%%-*}"
    KSUNEXT_BASE_COMMIT=$(git -C "$KSU_DIR" merge-base HEAD "refs/remotes/origin/${KSUNEXT_BASE_BRANCH}" 2>/dev/null \
        || git -C "$KSU_DIR" merge-base HEAD refs/remotes/origin/main 2>/dev/null \
        || echo HEAD)
else
    KSUNEXT_BASE_COMMIT="HEAD"
fi

ksu_git_version "v0.0.1" 0 "$KSUNEXT_BASE_COMMIT"
ksu_publish_version
ksu_enable_configs CONFIG_KSU

log "KernelSU-Next ready ✅"
