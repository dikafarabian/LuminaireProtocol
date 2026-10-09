#!/usr/bin/env bash

# ======================================================
# 🔓 CORE — Protected Exports Removal
# ======================================================
# Drops the GKI protected exports list and protected modules

rm -rf "${KERNEL_SRC}/android/abi_gki_protected_exports_"*

sed -i '/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$/d' \
    "${KERNEL_SRC}/BUILD.bazel" 2>/dev/null || true

sed -i 's/protected_modules = \[.*\]/protected_modules = []/' \
    "${KERNEL_SRC}/modules.bzl" 2>/dev/null || true

log "Protected exports removed ✅"
