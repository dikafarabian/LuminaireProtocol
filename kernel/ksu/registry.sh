#!/usr/bin/env bash

# ======================================================
# 🗂️ REGISTRY — Root Solutions
# ======================================================
# Supported kernel versions per KSU variant come from kernel/features.json

source "${ROOT_DIR}/kernel/ksu/common.sh"

ksu_variant_supports_kernel_version() {
    feature_supports_kernel_version ksu "$1"
}
