#!/usr/bin/env bash

rm -rf "${KERNEL_SRC}/android/abi_gki_protected_exports_"*

# Kleaf: also drop the Bazel references to the deleted lists, or
# //common:kernel_aarch64 fails to load them at analysis time
sed -i '/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$/d' \
    "${KERNEL_SRC}/BUILD.bazel" 2>/dev/null || true

sed -i 's/protected_modules = \[.*\]/protected_modules = []/' \
    "${KERNEL_SRC}/modules.bzl" 2>/dev/null || true

log "Protected exports removed ✅"
