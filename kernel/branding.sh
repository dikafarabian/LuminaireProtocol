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

log "Branding: ${BUILD_USER:-(stock)}@${BUILD_HOST:-(stock)} | ${LOCALVERSION:-(stock, no LOCALVERSION)} ✅"
