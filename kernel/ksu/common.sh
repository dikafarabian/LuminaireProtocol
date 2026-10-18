#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — Shared Steps
# ======================================================
# Steps every variant in variants/ runs: preseed, setup, version, configs

source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"

ksu_preseed() {
    local key="$1" ref_var="${1^^}_REF" candidate_var="CANDIDATE_${1^^}"
    mirror_preseed "$key" "$KSU_DIR" "${!ref_var:-}" "${!candidate_var:-false}" "$(resolve_android_version)-${KERNEL_VERSION}" || true
}

ksu_patcher() {
    python3 "${ROOT_DIR}/kernel/ksu/variants/${KERNEL_VARIANT,,}/$1" "${@:2}"
}

ksu_integrate() {
    local name="$1" setup_url="$2" setup_ref="$3" preseed_key="${4:-}"
    log "Integrating ${name}..."
    cd "$KERNEL_SRC"
    [ -z "$preseed_key" ] || ksu_preseed "$preseed_key"
    run_upstream_setup "$name" "$setup_url" "$setup_ref"
    [ -d "$KSU_DIR" ] || error "${name}: $(basename "$KSU_DIR") dir not found after setup!"
    verify_pinned_ref "$name" "$KSU_DIR" "$setup_ref"
    cd "$ROOT_DIR"
    log "${name} integrated ✅"
}

ksu_git_version() {
    local default_tag="$1" offset="${2:-0}" rev="${3:-HEAD}" count
    count=$(git -C "$KSU_DIR" rev-list --count "$rev" 2>/dev/null || echo 0)
    KSU_VERSION_CODE=$((30000 + count + offset))
    KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --tags --abbrev=0 "$rev" 2>/dev/null || echo "$default_tag")
}

ksu_publish_version() {
    KSU_UAPI_VERSION="$(ksu_uapi_version "$KSU_DIR")"
    VARIANT_VERSION_DISPLAY="$(format_ksu_version "$KSU_TAG_NAME" "$KSU_VERSION_CODE" "$KSU_UAPI_VERSION")"
    log "Version: ${VARIANT_VERSION_DISPLAY}"
}

ksu_enable_configs() {
    log "Enabling KSU configs..."
    gki_defconfig_enable "$@"
    log "Configs enabled ✅"
}
