#!/usr/bin/env bash

# ======================================================
# 🪟 ADDON — NTSync
# Driver by Elizabeth Figura (CodeWeavers), GKI backport by luigimak & fatalcoder524
# Patch source: https://github.com/WildKernels/kernel_patches
# ======================================================

NTSYNC_PATCHES_BASE="https://github.com/WildKernels/kernel_patches/raw/main/common/ntsync"

NTSYNC_COMPAT="ntsync_compat_${ANDROID_VERSION}-${KERNEL_VERSION}.patch"

log "🪟 Applying NTSync patches (base + ${NTSYNC_COMPAT})..."
for NTSYNC_PATCH_FILE in "ntsync_base.patch" "${NTSYNC_COMPAT}"; do
    apply_remote_patch "NTSync (${NTSYNC_PATCH_FILE})" "${NTSYNC_PATCHES_BASE}/${NTSYNC_PATCH_FILE}" "$KERNEL_SRC"
done
gki_defconfig_enable CONFIG_NTSYNC

log "NTSync driver integrated ✅"
