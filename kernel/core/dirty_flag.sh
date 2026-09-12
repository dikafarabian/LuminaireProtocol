#!/usr/bin/env bash

sed -i 's/-dirty//' "${KERNEL_SRC}/scripts/setlocalversion"

# Kleaf computes the dirty flag from stamp.bzl's scmversion command instead
if [ -f "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl" ]; then
    sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" \
        "${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
fi

# KLEAF: repo-synced workspace has a detached HEAD and no git identity worth
# faking; the stamp.bzl patch above covers it. MAKE: amend a commit so
# setlocalversion sees a clean tree.
if [ "$BUILD_SYSTEM" != "KLEAF" ]; then
    cd "${KERNEL_SRC}"
    git config --local user.name "${BUILD_USER:-chainonyourdoor}"
    git config --local user.email "${BUILD_USER:-chainonyourdoor}@users.noreply.github.com"
    git add . > /dev/null 2>&1 && { git commit --amend --no-edit --quiet 2>/dev/null || git commit -m "Luminaire: Clean dirty flags" --quiet; } \
        || warn "dirty_flag: git commit failed (tree may already be clean or git not initialized — dirty flag may persist in version string)"
    cd "${ROOT_DIR}"
fi
log "Dirty flags cleaned ✅"
