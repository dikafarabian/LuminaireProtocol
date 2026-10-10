#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — NoMount (VFS path injection framework)
# ======================================================
# Repo: https://github.com/maxsteeel/nomount
# Integration: upstream automatic built-in setup.sh (Method 1)
# ======================================================

NOMOUNT_SETUP_URL="https://raw.githubusercontent.com/maxsteeel/nomount/refs/heads/dev/kernel/setup.sh"
NOMOUNT_SETUP="/tmp/nomount_setup.sh"

log "Fetching NoMount setup script..."
retry 3 run_quiet curl -fSL "$NOMOUNT_SETUP_URL" -o "$NOMOUNT_SETUP" \
    || { addon_skip "NoMount setup script download failed — skipping"; return 0; }

if [ -d "${KERNEL_SRC}/fs" ]; then
    NOMOUNT_FS_DIR="${KERNEL_SRC}/fs"
elif [ -d "${KERNEL_SRC}/common/fs" ]; then
    NOMOUNT_FS_DIR="${KERNEL_SRC}/common/fs"
else
    addon_skip "NoMount: fs/ directory not found under ${KERNEL_SRC} — skipping"
    rm -f "$NOMOUNT_SETUP"
    return 0
fi

log "Integrating NoMount (built-in)..."
( cd "$KERNEL_SRC" && bash "$NOMOUNT_SETUP" ) \
    || { addon_skip "NoMount setup script failed — skipping"; rm -f "$NOMOUNT_SETUP"; return 0; }
rm -f "$NOMOUNT_SETUP"

if [ ! -L "${NOMOUNT_FS_DIR}/nomount" ] \
        || ! grep -q "nomount" "${NOMOUNT_FS_DIR}/Makefile" \
        || ! grep -q 'source "fs/nomount/Kconfig"' "${NOMOUNT_FS_DIR}/Kconfig"; then
    addon_skip "NoMount integration incomplete — kernel will build without NoMount"
    return 0
fi
log "NoMount integrated ✅"

log "Enabling NoMount config..."
gki_defconfig_enable CONFIG_NOMOUNT

NOMOUNT_VERSION="$(sed -n 's/^version=//p' "${KERNEL_SRC}/NoMount/module/module.prop" 2>/dev/null | head -n 1 | tr -d '[:space:]')" || true
if [ -n "$NOMOUNT_VERSION" ]; then
    github_env NOMOUNT_VERSION "${NOMOUNT_VERSION}"
    log "NoMount version: ${NOMOUNT_VERSION}"
fi

log "NoMount setup done ✅"
