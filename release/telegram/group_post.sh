#!/usr/bin/env bash

TELEGRAM_DIR="${LUMINAIRE_PATCH_DIR}/release/telegram"

source "${LUMINAIRE_PATCH_DIR}/functions.sh"
source "${TELEGRAM_DIR}/config.sh"
source "${TELEGRAM_DIR}/common.sh"

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-300}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"
TELEGRAM_MAX_FILE_BYTES=$((50 * 1024 * 1024))

STAGE_DIR="${STAGE_DIR:-/tmp/group-stage}"
LINKS_DIR="${LINKS_DIR:-${GITHUB_WORKSPACE:-$PWD}/variant-links}"
FILE_IDS_FILE="/tmp/group_post_file_ids.json"
PAYLOAD_FILE="/tmp/group_post_payload.json"
ATTACHMENTS_FILE="/tmp/group_post_attachments.txt"
RESPONSE_FILE="/tmp/group_post_response.json"
STAGED_MESSAGE_IDS=()

cleanup() {
    local message_id
    for message_id in "${STAGED_MESSAGE_IDS[@]}"; do
        telegram_api_call "deleteMessage" "$RESPONSE_FILE" "Staging cleanup" \
            -d "chat_id=${STAGING_CHAT_ID}" -d "message_id=${message_id}" || true
    done
    rm -f "$FILE_IDS_FILE" "$PAYLOAD_FILE" "$ATTACHMENTS_FILE" "$RESPONSE_FILE"
}

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "Skipping group post: TELEGRAM_BOT_TOKEN not set"
    exit 0
fi
if [ ! -d "$STAGE_DIR" ] || [ -z "$(find "$STAGE_DIR" -name meta.json -print -quit)" ]; then
    warn "Skipping group post: no staged variants in ${STAGE_DIR}"
    exit 0
fi

RUN_MODE_UPPER="${RUN_MODE^^}"
case "$RUN_MODE_UPPER" in
    BUILD)   TARGET_THREAD_ID="${TELEGRAM_THREAD_ID_BUILD_BY_VERSION[$KERNEL_VERSION]:-}" ;;
    RELEASE) TARGET_THREAD_ID="${TELEGRAM_THREAD_ID_RELEASE:-}" ;;
    *)       error "Telegram: unknown RUN_MODE '${RUN_MODE:-}' — expected Build or Release" ;;
esac

STAGING_CHAT_ID="${TELEGRAM_PERSONAL_CHAT_ID:-}"
[ -n "$STAGING_CHAT_ID" ] || error "TELEGRAM_PERSONAL_CHAT_ID not set — needed to stage zip uploads"

if [ "${DELIVERY_TARGET:-Group}" = "Private" ]; then
    TARGET_CHAT_ID="$STAGING_CHAT_ID"
    TARGET_THREAD_ID=""
else
    [ -n "${TELEGRAM_CHAT_ID:-}" ] || error "TELEGRAM_CHAT_ID not set"
    [ -n "$TARGET_THREAD_ID" ] || error "No thread id configured for RUN_MODE=${RUN_MODE}, KERNEL_VERSION=${KERNEL_VERSION:-}"
    TARGET_CHAT_ID="$TELEGRAM_CHAT_ID"
fi

trap cleanup EXIT

OVERSIZED=()
while IFS= read -r meta; do
    zip_file="$(dirname "$meta")/$(jq -r '.zip_name' "$meta")"
    zip_bytes=$(stat -c%s "$zip_file" 2>/dev/null || echo 0)
    if [ "$zip_bytes" -eq 0 ] || [ "$zip_bytes" -gt "$TELEGRAM_MAX_FILE_BYTES" ]; then
        warn "Excluding $(basename "$zip_file"): $((zip_bytes / 1024 / 1024))MB (empty or over Telegram's 50MB upload limit)"
        OVERSIZED+=("$(basename "$zip_file")")
        rm -f "$meta"
    fi
done < <(find "$STAGE_DIR" -name meta.json | sort)

if [ -z "$(find "$STAGE_DIR" -name meta.json -print -quit)" ]; then
    error "Group post aborted: no variant zip is eligible for upload"
fi

echo '{}' > "$FILE_IDS_FILE"
while IFS= read -r meta; do
    variant="$(jq -r '.variant' "$meta")"
    zip_name="$(jq -r '.zip_name' "$meta")"
    log "📤 Uploading ${zip_name}..."
    telegram_api_call "sendDocument" "$RESPONSE_FILE" "Upload ${zip_name}" \
        -F "chat_id=${STAGING_CHAT_ID}" \
        -F "disable_notification=true" \
        -F "document=@$(dirname "$meta")/${zip_name};filename=${zip_name}" \
        || error "Upload failed: ${zip_name}"
    file_id="$(jq -r '.result.document.file_id // empty' <<< "$TG_RESPONSE")"
    staged_id="$(jq -r '.result.message_id // empty' <<< "$TG_RESPONSE")"
    [ -n "$staged_id" ] && STAGED_MESSAGE_IDS+=("$staged_id")
    [ -n "$file_id" ] || error "Upload ${zip_name}: no file_id in response"
    jq --arg variant "$variant" --arg file_id "$file_id" '. + {($variant): $file_id}' "$FILE_IDS_FILE" > "${FILE_IDS_FILE}.new"
    mv "${FILE_IDS_FILE}.new" "$FILE_IDS_FILE"
done < <(find "$STAGE_DIR" -name meta.json | sort)

TELEGRAM_GROUP="${TELEGRAM_GROUP:-}" \
CHANGELOG="${CHANGELOG:-}" \
GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}" \
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" \
python3 "${TELEGRAM_DIR}/group_card.py" "$STAGE_DIR" "$FILE_IDS_FILE" "$PAYLOAD_FILE" "$ATTACHMENTS_FILE" \
    || error "Telegram: group card builder failed!"

mapfile -t ATTACHMENT_SPECS < "$ATTACHMENTS_FILE"

SEND_ARGS=(-F "chat_id=${TARGET_CHAT_ID}" -F "rich_message=<${PAYLOAD_FILE}")
for spec in "${ATTACHMENT_SPECS[@]}"; do
    SEND_ARGS+=(-F "$spec")
done
[ -n "$TARGET_THREAD_ID" ] && SEND_ARGS+=(-F "message_thread_id=${TARGET_THREAD_ID}")

log "📨 Sending group post (${RUN_MODE_UPPER})..."
telegram_api_call "sendRichMessage" "$RESPONSE_FILE" "Group send" "${SEND_ARGS[@]}" \
    || error "Group post failed"

GROUP_MESSAGE_ID="$(jq -r '.result.message_id // empty' <<< "$TG_RESPONSE")"
log "Sent ✅ (message_id=${GROUP_MESSAGE_ID})"

if [ "${DELIVERY_TARGET:-Group}" != "Private" ] && [ "$RUN_MODE_UPPER" = "RELEASE" ] && [ -n "${TELEGRAM_CHANNEL_ID:-}" ]; then
    [ -n "$GROUP_MESSAGE_ID" ] || error "Group post sent but message_id could not be read — variant links not saved"
    GROUP_MSG_LINK="https://t.me/${TELEGRAM_CI_GROUP}/${GROUP_MESSAGE_ID}"
    mkdir -p "$LINKS_DIR"
    while IFS= read -r meta; do
        link_file="${LINKS_DIR}/$(jq -r '.variant' "$meta").json"
        jq --arg link "$GROUP_MSG_LINK" \
            '{variant, link: $link, linux_ver, kernel_version, ksu_version: .variant_version, compiler_string, lto_mode, addons, addon_order, skipped_addons, applied_tuning, skipped_tuning}' \
            "$meta" > "$link_file"
        log "Variant link saved → ${link_file} ✅"
    done < <(find "$STAGE_DIR" -name meta.json | sort)
fi

if [ "${#OVERSIZED[@]}" -gt 0 ]; then
    error "Group post sent without: ${OVERSIZED[*]} (over the upload limit)"
fi
