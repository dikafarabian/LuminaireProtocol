#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — Droidspaces (container namespace and cgroup support)
# ======================================================

log "Enabling Droidspaces support..."

GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
DROIDSPACES_CONFIGS=(
    CONFIG_SYSVIPC
    CONFIG_PID_NS
    CONFIG_IPC_NS
    CONFIG_UTS_NS
    CONFIG_DEVTMPFS
    CONFIG_CGROUP_DEVICE
    CONFIG_NET_NS
    CONFIG_NETFILTER_XT_TARGET_LOG
    CONFIG_NETFILTER_XT_MATCH_RECENT
    CONFIG_BINFMT_ELF
    CONFIG_BINFMT_SCRIPT
    CONFIG_USER_NS
)
MISSING_CONFIGS=()
for cfg in "${DROIDSPACES_CONFIGS[@]}"; do
    grep -q "^${cfg}=y" "$GKI_DEFCONFIG" || MISSING_CONFIGS+=("${cfg}=y")
done
if [ "${#MISSING_CONFIGS[@]}" -gt 0 ]; then
    for cfg in "${DROIDSPACES_CONFIGS[@]}"; do
        sed -i "/^# ${cfg} is not set$/d" "$GKI_DEFCONFIG"
    done
    {
        echo ""
        echo "# Droidspaces — added by addon (missing from base defconfig)"
        printf '%s\n' "${MISSING_CONFIGS[@]}"
    } >> "$GKI_DEFCONFIG"
    log "Droidspaces: added ${#MISSING_CONFIGS[@]} missing config(s): ${MISSING_CONFIGS[*]}"
else
    log "Droidspaces: all required configs already present"
fi
log "Droidspaces configs enabled ✅"
