#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KernelSU (official, tiann)
# ======================================================
# Repo: https://github.com/tiann/KernelSU

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"

log "Integrating KernelSU (official)..."
cd "$KERNEL_SRC"
mirror_preseed "ksu" "$KSU_DIR" "${KSU_REF:-}" "${CANDIDATE_KSU:-false}" "$(resolve_android_version)-${KERNEL_VERSION}" || true
run_upstream_setup "KernelSU" "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" "${KSU_REF:-}"
[ -d "$KSU_DIR" ] || error "KernelSU: KernelSU dir not found after setup!"
verify_pinned_ref "KernelSU" "$KSU_DIR" "${KSU_REF:-}"
cd "$ROOT_DIR"
log "KernelSU integrated ✅"

log "Branding skipped (official KernelSU exposes no version-tag string) ✅"

KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --tags --abbrev=0 2>/dev/null || echo "v0.9.5")
KSU_LOCAL_VERSION=$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
KSU_VERSION_CODE=$((30000 + KSU_LOCAL_VERSION))
KSU_UAPI_VERSION="$(ksu_uapi_version "$KSU_DIR")"
KSU_VERSION_DISPLAY="$(format_ksu_version "$KSU_TAG_NAME" "$KSU_VERSION_CODE" "$KSU_UAPI_VERSION")"
github_env KSU_VERSION_DISPLAY "${KSU_VERSION_DISPLAY}"
log "Version: ${KSU_VERSION_DISPLAY}"

log "Enabling KSU configs..."
gki_defconfig_enable CONFIG_KSU
log "Configs enabled ✅"

log "KernelSU ready ✅"