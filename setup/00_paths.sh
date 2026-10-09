#!/usr/bin/env bash

# ======================================================
# 🧭 SETUP — Paths & Build System
# ======================================================

case "${BUILD_SYSTEM:-Make - Cirrus}" in
    "Kleaf - AOSP" | KLEAF)
        BUILD_SYSTEM="KLEAF"
        CLANG_VARIANT="aosp"
        ;;
    Make\ -\ *)
        CLANG_VARIANT="${BUILD_SYSTEM##Make - }"
        CLANG_VARIANT="${CLANG_VARIANT,,}"
        BUILD_SYSTEM="MAKE"
        ;;
    MAKE)
        BUILD_SYSTEM="MAKE"
        CLANG_VARIANT="${CLANG_VARIANT:-cirrus}"
        ;;
    *)
        warn "Unknown BUILD_SYSTEM input '${BUILD_SYSTEM}', defaulting to MAKE + cirrus"
        BUILD_SYSTEM="MAKE"
        CLANG_VARIANT="cirrus"
        ;;
esac
export BUILD_SYSTEM CLANG_VARIANT

KLEAF_MANIFEST_BRANCH="common-${ANDROID_VERSION}-${KERNEL_VERSION}-lts"

: "${ROOT_DIR:?ROOT_DIR must be set by the entrypoint before run_setup() runs}"

WORKSPACE_DIR="${ROOT_DIR}/workspace"
KERNEL_DIR="${WORKSPACE_DIR}/kernel"
KERNEL_SRC="${KERNEL_DIR}/common"
OUT_DIR="${WORKSPACE_DIR}/out"
KLEAF_OUT_DIR="${KERNEL_DIR}/bazel-bin/common/kernel_aarch64"
LTO_CACHE_DIR="/dev/shm/ldcache"

case "${KERNEL_VERSION}" in
    5.10)              KABI_PATCHES=(sysvipc_below_6_12 posix_mqueue_5_10) ;;
    5.15|6.1|6.6)      KABI_PATCHES=(sysvipc_below_6_12) ;;
    6.12)              KABI_PATCHES=(sysvipc_6_12) ;;
esac

DEFCONFIG="gki_defconfig"
ARCH="arm64"

TOOL_CLANG_DIR="${ROOT_DIR}/clang"
TOOL_AK3_DIR="${WORKSPACE_DIR}/AnyKernel3"
TOOL_CCACHE_BIN="${ROOT_DIR}/ccache-bin/ccache"
TOOL_CCACHE_WRAPPERS="${ROOT_DIR}/ccache-wrappers"
TOOL_CROSS_COMPILE="aarch64-linux-gnu-"
TOOL_CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"

export GIT_CLONE_PROTECTION_ACTIVE=false
export KCFLAGS="-w"

log "Paths configured ✅ (Build System: ${BUILD_SYSTEM}, Clang: ${CLANG_VARIANT})"

BRANDING_KLEAF_ARGS=()
