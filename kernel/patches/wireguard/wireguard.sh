#!/usr/bin/env bash

# ======================================================
# 🔒 PATCH — WireGuard (kernel-level VPN)
# ======================================================
# Upstream: https://www.wireguard.com/
# ======================================================

gki_defconfig_enable CONFIG_WIREGUARD

log "WireGuard kernel-level VPN support enabled ✅"
