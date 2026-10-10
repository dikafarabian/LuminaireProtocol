#!/usr/bin/env bash

# ======================================================
# 🚀 PATCH — BBRv3
# TCP congestion control backport by fatalcoder524
# Patch source: https://github.com/WildKernels/kernel_patches
# ======================================================

BBRV3_PATCHES_BASE="https://github.com/WildKernels/kernel_patches/raw/main/common/bbrv3"

case "${KERNEL_VERSION}" in
    5.10) BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android12-5.10.patch" ;;
    5.15) BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android13-5.15.patch" ;;
    6.1)  BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android14-6.1.patch"  ;;
    6.6)  BBRV3_PATCH="0001-net-tcp-backport-BBRv3-to-android15-6.6.patch"  ;;
    *)    error "BBRv3: unsupported kernel version '${KERNEL_VERSION}'" ;;
esac

log "🚀 Applying BBRv3 patch (${BBRV3_PATCH})..."
apply_remote_patch "BBRv3" "${BBRV3_PATCHES_BASE}/${BBRV3_PATCH}" "$KERNEL_SRC" --no-backup-if-mismatch
gki_defconfig_enable CONFIG_TCP_CONG_ADVANCED CONFIG_TCP_CONG_BBR3 CONFIG_DEFAULT_BBR3

cd "${KERNEL_SRC}"
if [ "${KERNEL_VERSION}" = "5.10" ]; then
    SYSCTL_PATCH=$(fetch "${BBRV3_PATCHES_BASE}/sysctl_add_proc_dou8vec_minmax.patch") || true
    if [ -n "$SYSCTL_PATCH" ]; then
        if ! grep -qF 'int proc_dou8vec_minmax(' "${KERNEL_SRC}/include/linux/sysctl.h" 2>/dev/null; then
            echo "$SYSCTL_PATCH" | patch -p1 --forward --no-backup-if-mismatch || true
            SYSCTL_FIX=$(fetch "${BBRV3_PATCHES_BASE}/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch") || true
            [ -n "$SYSCTL_FIX" ] && echo "$SYSCTL_FIX" | patch -p1 --forward --no-backup-if-mismatch || true
        fi
    fi
fi

python3 "${ROOT_DIR}/kernel/patches/bbrv3/enforcer.py" "${KERNEL_SRC}/net/ipv4/tcp_cong.c" \
    || error "BBRv3: enforcer injection into tcp_cong.c failed!"

cd "${ROOT_DIR}"

log "BBRv3 patch applied, default-congestion enforcer injected ✅"
