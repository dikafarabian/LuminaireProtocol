#!/usr/bin/env bash

# ======================================================
# 🔑 ROOT SOLUTION — KowSU
# ======================================================
# Repo: https://github.com/KOWX712/KernelSU
# Note: KowSU's manager app (com.kowx712.supermanager) does not expose a
# separate kernel driver version field the way ReSukiSU's manager does, so
# Luminaire branding is intentionally NOT applied for this variant (cosmetic
# only, no functional impact — see project decision).

KSU_DIR="${KERNEL_SRC}/KernelSU"
PATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"

log "Integrating KowSU..."
cd "$KERNEL_SRC"
mirror_preseed "kowsu" "$KSU_DIR" "${KOWSU_REF:-}" "${CANDIDATE_KOWSU:-false}" "$(resolve_android_version)-${KERNEL_VERSION}" || true
run_upstream_setup "KowSU" "https://raw.githubusercontent.com/KOWX712/KernelSU/main/kernel/setup.sh" "${KOWSU_REF:-}"
[ -d "$KSU_DIR" ] || error "KowSU: KernelSU dir not found after setup!"
verify_pinned_ref "KowSU" "$KSU_DIR" "${KOWSU_REF:-}"
cd "$ROOT_DIR"
log "KowSU integrated ✅"

KSU_TAG_NAME=$(git -C "$KSU_DIR" describe --abbrev=0 --tags 2>/dev/null || echo "v0.0.1")
KSU_LOCAL_VERSION=$(git -C "$KSU_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
KSU_VERSION_CODE=$((30000 + KSU_LOCAL_VERSION))
KSU_UAPI_VERSION="$(ksu_uapi_version "$KSU_DIR")"
KOWSU_VERSION_DISPLAY="$(format_ksu_version "$KSU_TAG_NAME" "$KSU_VERSION_CODE" "$KSU_UAPI_VERSION")"
github_env KOWSU_VERSION_DISPLAY "${KOWSU_VERSION_DISPLAY}"
log "Version: ${KOWSU_VERSION_DISPLAY}"

log "Enabling KSU configs..."
gki_defconfig_enable CONFIG_KSU
log "Configs enabled ✅"

log "KowSU ready ✅"
