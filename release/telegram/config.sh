#!/usr/bin/env bash

# ======================================================
# 📨 TELEGRAM — Post Configuration
# ======================================================

TELEGRAM_API_BASE="${TELEGRAM_API_BASE:-https://api.telegram.org}"
TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_UPLOAD_TIMEOUT="${TELEGRAM_UPLOAD_TIMEOUT:-900}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"

TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
TELEGRAM_GROUP="LuminaireLab"

declare -A TELEGRAM_THREAD_ID_BUILD_BY_VERSION=(
    ["5.10"]="605"
    ["5.15"]="606"
    ["6.1"]="626"
    ["6.6"]="751"
    ["6.12"]="755"
)

TELEGRAM_CHANNEL_ID="${TELEGRAM_CHANNEL_ID:-}"
