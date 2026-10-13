#!/usr/bin/env bash

# ======================================================
# 🧩 CONFIG — Luminaire Defconfig (Kleaf)
# ======================================================
# Applies luminaire.fragment and feature configs directly to gki_defconfig

log "Applying Luminaire configs (fragment)..."
DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
RE_CONFIG_SET='^(CONFIG_[^=]+)=(.*)$'
RE_CONFIG_UNSET_GUARD='^(# CONFIG_[^ ]+) is not set$'
RE_CONFIG_UNSET_EXTRACT='^# (CONFIG_[^ ]+) is not set$'

while IFS= read -r line; do
    [[ "$line" =~ $RE_CONFIG_SET ]] || \
    [[ "$line" =~ $RE_CONFIG_UNSET_GUARD ]] || continue

    if [[ "$line" =~ ^CONFIG_([^=]+)=(.*)$ ]]; then
        key="CONFIG_${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        sed -i "/^${key}[= ]/d;/^# ${key} is not set/d" "$DEFCONFIG_FILE"
        echo "${key}=${val}" >> "$DEFCONFIG_FILE"
    elif [[ "$line" =~ $RE_CONFIG_UNSET_EXTRACT ]]; then
        key="CONFIG_${BASH_REMATCH[1]}"
        sed -i "/^${key}[= ]/d;/^# ${key} is not set/d" "$DEFCONFIG_FILE"
        echo "# ${key} is not set" >> "$DEFCONFIG_FILE"
    fi
done < <(grep -E '^CONFIG_|^# CONFIG_' "${ROOT_DIR}/kernel/config/luminaire.fragment")
log "Fragment applied ✅"

if [ "${BBG_ENABLED:-false}" = "true" ]; then
    log "BBG: patching CONFIG_LSM before config pass..."
    CURRENT_LSM=$(grep -oP '^CONFIG_LSM="\K[^"]+' "$DEFCONFIG_FILE" || true)
    if [ -z "$CURRENT_LSM" ]; then
        CURRENT_LSM=$(grep -oP '^\tdefault "\K[^"]+(?="$)' "${KERNEL_SRC}/security/Kconfig" | tail -1)
        [ -n "$CURRENT_LSM" ] || error "BBG: could not determine CONFIG_LSM default from security/Kconfig!"
    fi
    if [[ ",${CURRENT_LSM}," == *",baseband_guard,"* ]]; then
        log "BBG: baseband_guard already in CONFIG_LSM ✅"
    else
        sed -i "/^CONFIG_LSM=/d" "$DEFCONFIG_FILE"
        echo "CONFIG_LSM=\"${CURRENT_LSM},baseband_guard\"" >> "$DEFCONFIG_FILE"
        log "BBG: baseband_guard appended to CONFIG_LSM ✅"
    fi
fi
