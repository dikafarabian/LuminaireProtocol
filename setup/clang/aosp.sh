#!/usr/bin/env bash

# ======================================================
# 🧰 CLANG VARIANT — AOSP (mirrored by bachnxuan/aosp_clang_mirror)
# ======================================================

log "Downloading AOSP Clang..."

AOSP_URL=$(latest_release_asset_url "bachnxuan/aosp_clang_mirror" ".tar.gz") \
    || error "AOSP: failed to query GitHub API!"
[ -n "$AOSP_URL" ] || error "AOSP: no .tar.gz asset found in latest release!"

retry 3 run_quiet curl -fL "$AOSP_URL" -o /tmp/clang.tar.gz \
    || error "AOSP: download failed!"

tar -xf /tmp/clang.tar.gz -C "$TOOL_CLANG_DIR"
rm -f /tmp/clang.tar.gz
log "AOSP Clang downloaded ✅"
