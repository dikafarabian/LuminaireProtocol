#!/usr/bin/env bash

# ======================================================
# 🛡️ PATCH — le9uo (working set protection)
# ======================================================

LE9UO_PATCH="${ROOT_DIR}/kernel/patches/le9uo/le9uo-v1.15.patch"

log "🛡️ Applying le9uo working set protection patch..."
apply_patch "le9uo" "$LE9UO_PATCH" "$KERNEL_SRC" --fuzz=3

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
sed -i '/^# le9uo Working Set Protection (Luminaire) — active from boot$/d; /^CONFIG_WORKINGSET_PROTECTION_ENABLED=y$/d; /^CONFIG_ANON_MIN_RATIO=[0-9]*$/d; /^CONFIG_CLEAN_LOW_RATIO=[0-9]*$/d; /^CONFIG_CLEAN_MIN_RATIO=[0-9]*$/d' "$DEFCONFIG_FILE"
cat >> "$DEFCONFIG_FILE" << 'DEFEOF'
# le9uo Working Set Protection (Luminaire) — active from boot
CONFIG_WORKINGSET_PROTECTION_ENABLED=y
CONFIG_ANON_MIN_RATIO=5
CONFIG_CLEAN_LOW_RATIO=0
CONFIG_CLEAN_MIN_RATIO=5
DEFEOF
log "le9uo: defconfig forced (protection active from first boot, anon/clean min ratio 5%) ✅"

LE9UO_VERSION="$(basename "$LE9UO_PATCH" .patch | sed 's/^le9uo-//')"
github_env LE9UO_VERSION "$LE9UO_VERSION"

log "le9uo Working Set Protection integrated ✅"
