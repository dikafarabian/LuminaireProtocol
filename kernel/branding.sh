#!/usr/bin/env bash

SUBLEVEL="$(grep '^SUBLEVEL = ' "${KERNEL_SRC}/Makefile" | awk '{print $3}')" || true
[ -n "$SUBLEVEL" ] || error "SUBLEVEL not found in kernel Makefile — kernel source may be missing or corrupted!"
KMI_GENERATION="$(grep '^KMI_GENERATION=' \
    "${KERNEL_SRC}/build.config.common" \
    "${KERNEL_SRC}/build.config.constants" 2>/dev/null | head -1 | cut -d= -f2)" || true
[ -z "$KMI_GENERATION" ] && error "KMI_GENERATION not found!"
export SUBLEVEL KMI_GENERATION
echo "SUBLEVEL=${SUBLEVEL}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

if [ -n "$BUILD_USER_OVERRIDE" ]; then
    export BUILD_USER="$BUILD_USER_OVERRIDE"
    export KBUILD_BUILD_USER="$BUILD_USER"
else
    unset BUILD_USER KBUILD_BUILD_USER
fi
if [ -n "$BUILD_HOST_OVERRIDE" ]; then
    export BUILD_HOST="$BUILD_HOST_OVERRIDE"
    export KBUILD_BUILD_HOST="$BUILD_HOST"
else
    unset BUILD_HOST KBUILD_BUILD_HOST
fi

if [ -n "$LOCALVERSION_OVERRIDE" ]; then
    export LOCALVERSION="$LOCALVERSION_OVERRIDE"
else
    unset LOCALVERSION
    log "LOCALVERSION_OVERRIDE empty — using stock kernel versioning (no custom tag)"
fi
export KBUILD_BUILD_TIMESTAMP="$(date '+%a %b %d %T %Z %Y')"

# -------------------------------------------------------
# MAKE
# -------------------------------------------------------
if [ "$BUILD_SYSTEM" != "KLEAF" ]; then
    log "Branding: ${BUILD_USER:-(stock)}@${BUILD_HOST:-(stock)} | ${LOCALVERSION:-(stock, no LOCALVERSION)} ✅"
    return 0
fi

# -------------------------------------------------------
# KLEAF
# -------------------------------------------------------

BRAND_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if [ -n "${LOCALVERSION:-}" ] && [ -f "$BRAND_DEFCONFIG" ]; then
    if grep -q "^CONFIG_LOCALVERSION=" "$BRAND_DEFCONFIG"; then
        sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"${LOCALVERSION}\"|" "$BRAND_DEFCONFIG"
    else
        echo "CONFIG_LOCALVERSION=\"${LOCALVERSION}\"" >> "$BRAND_DEFCONFIG"
    fi
    log "Kleaf CONFIG_LOCALVERSION patched (${LOCALVERSION}) ✅"
fi

MKCOMPILE_H="${KERNEL_SRC}/scripts/mkcompile_h"
if [ -f "$MKCOMPILE_H" ]; then
    if [ -n "${BUILD_USER:-}" ]; then
        sed -i "s/\(LINUX_COMPILE_BY=\).*/\1\"${BUILD_USER}\"/" "$MKCOMPILE_H"
    fi
    if [ -n "${BUILD_HOST:-}" ]; then
        sed -i "s/\(LINUX_COMPILE_HOST=\).*/\1\"${BUILD_HOST}\"/" "$MKCOMPILE_H"
    fi
    log "mkcompile_h patched ✅"
    grep -n "LINUX_COMPILE_BY\|LINUX_COMPILE_HOST" "$MKCOMPILE_H" \
        | while IFS= read -r l; do log "  $l"; done || true
else
    warn "mkcompile_h not found at: $MKCOMPILE_H"
fi

BUILD_EPOCH="$(date +%s)"
STAMP_BZL="${KERNEL_DIR}/build/kernel/kleaf/impl/stamp.bzl"
if [ -f "$STAMP_BZL" ]; then
    sed -i "s/export SOURCE_DATE_EPOCH=0/export SOURCE_DATE_EPOCH=${BUILD_EPOCH}/" "$STAMP_BZL"
    log "stamp.bzl SOURCE_DATE_EPOCH patched ✅"
else
    warn "stamp.bzl not found at: $STAMP_BZL"
fi

BRANDING_KLEAF_ARGS=(
    --noincompatible_strict_action_env
)
[ -n "${BUILD_USER:-}" ] && BRANDING_KLEAF_ARGS+=( --action_env=KBUILD_BUILD_USER="${BUILD_USER}" )
[ -n "${BUILD_HOST:-}" ] && BRANDING_KLEAF_ARGS+=( --action_env=KBUILD_BUILD_HOST="${BUILD_HOST}" )

log "Branding: ${BUILD_USER:-(stock)}@${BUILD_HOST:-(stock)} | ${LOCALVERSION:-(stock, no LOCALVERSION)} ✅"
