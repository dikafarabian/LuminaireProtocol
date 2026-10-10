#!/usr/bin/env bash

# ======================================================
# 🏗️ BUILD — MAKE (Kbuild)
# ======================================================

MAKE_ARGS=(
    -C "$KERNEL_SRC"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CROSS_COMPILE="$TOOL_CROSS_COMPILE"
    CROSS_COMPILE_COMPAT="$TOOL_CROSS_COMPILE_COMPAT"
    CC_COMPAT="${TOOL_CROSS_COMPILE_COMPAT}gcc"
    LLVM=1
    LLVM_IAS=1
    BRANCH="${KERNEL_BRANCH}"
    KMI_GENERATION="${KMI_GENERATION}"
    LOCALVERSION="${LOCALVERSION}"
    KBUILD_BUILD_USER="${KBUILD_BUILD_USER}"
    KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"
    -j"$(nproc --all)"
)

declare -A KBUILD_VERSION_LABEL=(
    [KSU]="KernelSU version"
    [KOWSU]="KernelSU version"
    [KSUNEXT]="KernelSU-Next version"
    [SUKISU]="SukiSU-Ultra version"
    [BAKASU]="BakaSU version code"
)

correct_version_display() {
    local label="${KBUILD_VERSION_LABEL[$KERNEL_VARIANT]:-}"
    local version_var="${KERNEL_VARIANT}_VERSION_DISPLAY" real_code real_display
    [ -n "$label" ] && [ -n "${KSU_TAG_NAME:-}" ] || return 0
    real_code="$(grep -oP -- "-- ${label}: \K[0-9]+" "$KBUILD_LOG" | tail -1 || true)"
    [ -n "$real_code" ] || return 0
    real_display="$(format_ksu_version "$KSU_TAG_NAME" "$real_code" "${KSU_UAPI_VERSION:-}")"
    [ "$real_display" = "${!version_var:-}" ] \
        || log "Correcting ${version_var} to match real Kbuild-computed version: ${real_display} (was: ${!version_var:-unset})"
    export "${version_var}=${real_display}"
    github_env "$version_var" "$real_display"
}

mkdir -p "$LTO_CACHE_DIR"

LD_JOBS=$(( $(nproc --all) / 2 ))
[ "$LD_JOBS" -ge 1 ] || LD_JOBS=1

NEEDS_WRAPPER=0
if [ "${LTO_MODE}" = "THIN" ]; then
    NEEDS_WRAPPER=1
elif [ "${LTO_MODE}" = "NONE" ] && [[ "${KERNEL_VERSION}" == 5.* ]]; then
    NEEDS_WRAPPER=1
fi

if [ "$NEEDS_WRAPPER" = "1" ]; then
    LD_WRAPPER="${KERNEL_SRC}/ld-wrapper"
    {
        echo '#!/usr/bin/env bash'
        if [ "${LTO_MODE}" = "THIN" ]; then
            echo "exec ld.lld \"\$@\" --thinlto-cache-dir=/dev/shm/ldcache --thinlto-jobs=${LD_JOBS} --threads=${LD_JOBS}"
        else
            echo "exec ld.lld \"\$@\" --threads=1"
        fi
    } > "$LD_WRAPPER"
    chmod +x "$LD_WRAPPER"
    MAKE_ARGS+=(LD="$LD_WRAPPER" HOSTLD="$LD_WRAPPER")

    if [ "${LTO_MODE}" = "THIN" ]; then
        log "ThinLTO ld-wrapper enabled (cache: /dev/shm/ldcache, jobs/threads: ${LD_JOBS}) ✅"
    else
        log "ld-wrapper enabled: kernel ${KERNEL_VERSION} + LTO_MODE=NONE (threads: 1, memory-bounded link) ✅"
    fi
fi

touch "${KERNEL_SRC}/.scmversion"

log "Generating defconfig..."
make "${MAKE_ARGS[@]}" "$DEFCONFIG" || error "Defconfig failed!"

log "Applying Luminaire configs..."
source "${ROOT_DIR}/kernel/config/defconfig.sh"

log "Syncing config..."
make "${MAKE_ARGS[@]}" olddefconfig || error "olddefconfig failed!"

log "Debug-info config:"
grep -E "^CONFIG_DEBUG_INFO|^# CONFIG_DEBUG_INFO" "${OUT_DIR}/.config" | while read -r line; do
    log "  ${line}"
done || true

log "Applying KaBI patches..."
apply_kabi_patches

CC_ARG="${TOOL_CCACHE_WRAPPERS}/clang"

if [ "${DRY_RUN:-false}" = "true" ]; then
    write_dry_run_image "${OUT_DIR}/arch/${ARCH}/boot/Image"
    BUILD_SECONDS=0
else
    log "Building kernel..."
    START_TIME=$(date +%s)

    KBUILD_LOG="${OUT_DIR}/.luminaire_kbuild.log"
    make "${MAKE_ARGS[@]}" CC="$CC_ARG" | tee "$KBUILD_LOG" || error "Build failed!"

    BUILD_SECONDS=$(( $(date +%s) - START_TIME ))
    log "Build completed in ${BUILD_SECONDS}s ✅"
fi
github_env BUILD_SECONDS "${BUILD_SECONDS}"

if [ "${DRY_RUN:-false}" != "true" ] && [ -f "${KBUILD_LOG:-}" ]; then
    correct_version_display
fi
