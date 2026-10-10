#!/usr/bin/env bash

# ======================================================
# 🪟 ADDON — NTSync
# Driver by Elizabeth Figura (CodeWeavers), GKI backport by luigimak & fatalcoder524
# Patch source: https://github.com/WildKernels/kernel_patches
# ======================================================

NTSYNC_PATCHES_BASE="https://github.com/WildKernels/kernel_patches/raw/main/common/ntsync"

case "${KERNEL_VERSION}" in
    5.10) NTSYNC_COMPAT="ntsync_compat_android12-5.10.patch" ;;
    5.15) NTSYNC_COMPAT="ntsync_compat_android13-5.15.patch" ;;
    6.1)  NTSYNC_COMPAT="ntsync_compat_android14-6.1.patch"  ;;
    6.6)  NTSYNC_COMPAT="ntsync_compat_android15-6.6.patch"  ;;
    6.12) NTSYNC_COMPAT="ntsync_compat_android16-6.12.patch" ;;
    *)    error "NTSync: unsupported kernel version '${KERNEL_VERSION}'" ;;
esac

log "🪟 Applying NTSync patches (base + ${NTSYNC_COMPAT})..."
for NTSYNC_PATCH_FILE in "ntsync_base.patch" "${NTSYNC_COMPAT}"; do
    apply_remote_patch "NTSync (${NTSYNC_PATCH_FILE})" "${NTSYNC_PATCHES_BASE}/${NTSYNC_PATCH_FILE}" "$KERNEL_SRC" --no-backup-if-mismatch
done
gki_defconfig_enable CONFIG_NTSYNC

log "NTSync driver integrated ✅"
