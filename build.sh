#!/usr/bin/env bash

# ======================================================
# ✨ BUILD — Luminaire Pipeline
# ======================================================
# Flow: setup → branding → root solution → core → patches → addons → build → release

set -eo pipefail

exec 2>&1

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${ROOT_DIR}/functions.sh"
enable_error_trace

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is not set}"

ANDROID_VERSION="$(resolve_android_version)"
KERNEL_BRANCH="$(resolve_kernel_branch)"

source "${ROOT_DIR}/kernel/core/registry.sh"
source "${ROOT_DIR}/kernel/addons/registry.sh"
source "${ROOT_DIR}/kernel/patches/registry.sh"
source "${ROOT_DIR}/kernel/kabi/registry.sh"
source "${ROOT_DIR}/kernel/ksu/registry.sh"

variant_label() {
    if [ "$SUSFS_ENABLED" = "true" ] && [ "$KERNEL_VARIANT" != "VANILLA" ]; then
        echo "${KERNEL_VARIANT}+SUSFS"
    else
        echo "${KERNEL_VARIANT}"
    fi
}

print_run_complete() {
    echo "========================================"
    echo "  $(mode_emoji "$RUN_MODE") ${RUN_MODE} Complete! $(mode_emoji "$RUN_MODE")"
    echo "  🏷️ $(variant_label)"
    echo "========================================"
}

main() {
    echo "========================================"
    echo "  ✨ Luminaire Protocol ✨"
    echo "========================================"
    echo "  🏷️ $(variant_label)"
    echo "  $(mode_emoji "$RUN_MODE") ${RUN_MODE}"
    echo "  🖥️ CPU: $(nproc --all) cores"
    echo "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo "  📅 $(date)"
    echo "========================================"

    run_setup

    echo "::group::⏳ Dependencies"
    wait_for_apt
    echo "::endgroup::"

    KSU_MANIFEST="${ROOT_DIR}/kernel/ksu/manifests/${ANDROID_VERSION}-${KERNEL_VERSION}.json"
    [ -f "$KSU_MANIFEST" ] \
        || error "Kernel version ${KERNEL_VERSION} is not yet supported — missing ${KSU_MANIFEST} (no KSU/patches implemented for this version)"

    mkdir -p "$KERNEL_DIR" "$OUT_DIR"

    restore_kernel_source
    run_branding
    mark_stage_ok CHECKPOINT_PRE_VARIANT_OK
    run_variant
    mark_stage_ok CHECKPOINT_VARIANT_OK
    run_core
    run_patches
    run_addons
    mark_stage_ok CHECKPOINT_ADDONS_OK
    run_build
    mark_stage_ok CHECKPOINT_BUILD_OK

    if [ "${RUN_MODE^^}" != "WARM RUN" ]; then
        run_release
    fi

    print_run_complete
}

restore_kernel_source() {
    echo "::group::📥 Kernel Source"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${ROOT_DIR}/build/kleaf/download.sh"
    else
        source "${ROOT_DIR}/build/make/download.sh"
    fi
    log "Kernel source ready ✅"
    echo "::endgroup::"
}

run_branding() {
    echo "::group::🔖 Branding"
    source "${ROOT_DIR}/kernel/branding/branding.sh"
    echo "::endgroup::"
}

run_variant() {
    if [ "$KERNEL_VARIANT" = "VANILLA" ]; then
        local ksu_kconfig_hook="${KERNEL_SRC}/drivers/kernelsu/Kconfig"
        if grep -q '^source "drivers/kernelsu/Kconfig"' "${KERNEL_SRC}/drivers/Kconfig" 2>/dev/null \
                && [ ! -f "$ksu_kconfig_hook" ]; then
            warn "Kernel source pre-wires a drivers/kernelsu/Kconfig hook (drivers/Kconfig) with no root solution selected — stubbing an empty Kconfig so olddefconfig doesn't choke on the missing file."
            mkdir -p "$(dirname "$ksu_kconfig_hook")"
            printf '# Stub — no root solution selected for this VANILLA build.\n' > "$ksu_kconfig_hook"
        fi
        return 0
    fi

    ksu_variant_supports_kernel_version "${KERNEL_VARIANT,,}" \
        || error "Root solution '${KERNEL_VARIANT}' is not available for kernel ${KERNEL_VERSION} — not listed in KSU_VARIANT_SUPPORTED_VERSIONS (kernel/ksu/registry.sh)."
    local script="${ROOT_DIR}/kernel/ksu/variants/${KERNEL_VARIANT,,}/${KERNEL_VARIANT,,}.sh"
    run_step "🍀" "Root Solution (${KERNEL_VARIANT})" "$script" \
        "Root solution '${KERNEL_VARIANT}' is marked supported for kernel ${KERNEL_VERSION} in KSU_VARIANT_SUPPORTED_VERSIONS but ${script} doesn't exist — the map is out of sync with kernel/ksu/variants/."

    [ "$SUSFS_ENABLED" = "true" ] || return 0
    local susfs_script="${ROOT_DIR}/kernel/ksu/susfs/susfs.sh"
    run_step "🧬" "SuSFS" "$susfs_script" "SuSFS script not found: $(basename "$susfs_script")"
}

run_build() {
    echo "::group::🏗️ Build Kernel (${BUILD_SYSTEM})"
    if [ "$BUILD_SYSTEM" = "KLEAF" ]; then
        source "${ROOT_DIR}/build/kleaf/compile.sh"
    else
        source "${ROOT_DIR}/build/make/compile.sh"
    fi
    echo "::endgroup::"
}

run_release() {
    echo "::group::🚀 Release"
    source "${ROOT_DIR}/release/anykernel.sh"
    source "${ROOT_DIR}/release/telegram/stage.sh"
    echo "::endgroup::"
}

main "$@"
