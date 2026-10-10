#!/usr/bin/env bash

# ======================================================
# 🧰 CLANG VARIANT — Cirrus (Greenforce Project)
# ======================================================

log "Downloading Cirrus Clang..."

CIRRUS_URL=$(latest_release_asset_url "greenforce-project/greenforce_clang" ".tar.gz") \
    || error "Cirrus: failed to query GitHub API!"
[ -n "$CIRRUS_URL" ] || error "Cirrus: no .tar.gz asset found in latest release!"

retry 3 run_quiet curl -fL "$CIRRUS_URL" -o /tmp/clang.tar.gz \
    || error "Cirrus: download failed!"
tar -xf /tmp/clang.tar.gz -C "$TOOL_CLANG_DIR" --strip-components=1
rm -f /tmp/clang.tar.gz
log "Cirrus Clang downloaded ✅"
