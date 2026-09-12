#!/usr/bin/env bash

# KLEAF uses the AOSP prebuilt clang — COMPILER_STRING is set by build/kleaf.sh
# AFTER the build (only detectable from the prebuilt binary), so nothing to patch here
[ "$BUILD_SYSTEM" = "KLEAF" ] && return 0

MKCOMPILE_H="${KERNEL_SRC}/scripts/mkcompile_h"
PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/core/compiler_string/patch.py"

[ -f "$MKCOMPILE_H" ] || { warn "mkcompile_h not found, skipping compiler string patch"; return 0; }

python3 "$PATCHER" "$MKCOMPILE_H" "$COMPILER_STRING" \
    || error "Compiler string patch failed!"

log "Compiler string patched in mkcompile_h ✅"
