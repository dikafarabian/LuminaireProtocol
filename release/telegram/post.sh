#!/usr/bin/env bash

TELEGRAM_DIR="${LUMINAIRE_PATCH_DIR}/release/telegram"

source "${LUMINAIRE_PATCH_DIR}/functions.sh"
source "${TELEGRAM_DIR}/config.sh"
source "${TELEGRAM_DIR}/common.sh"

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-900}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"

STAGE_DIR="${STAGE_DIR:-/tmp/post-stage}"
PAYLOAD_FILE="/tmp/post_payload.json"
ATTACHMENTS_FILE="/tmp/post_attachments.txt"
RESPONSE_FILE="/tmp/post_response.json"

cleanup() {
    rm -f "$PAYLOAD_FILE" "$ATTACHMENTS_FILE" "$RESPONSE_FILE"
}

send_post() {
    local chat_id="$1" thread_id="$2" with_banner="$3" label="$4"
    local -a attachment_specs send_args
    local message_id

    POST_BANNER="$with_banner" \
    TELEGRAM_GROUP="${TELEGRAM_GROUP:-}" \
    CHANGELOG="${CHANGELOG:-}" \
    GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}" \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" \
    python3 "${TELEGRAM_DIR}/post_card.py" "$STAGE_DIR" "$PAYLOAD_FILE" "$ATTACHMENTS_FILE" \
        || error "Telegram: ${label} builder failed!"

    mapfile -t attachment_specs < "$ATTACHMENTS_FILE"

    send_args=(-F "chat_id=${chat_id}" -F "rich_message=<${PAYLOAD_FILE}")
    for spec in "${attachment_specs[@]}"; do
        send_args+=(-F "$spec")
    done
    [ -n "$thread_id" ] && send_args+=(-F "message_thread_id=${thread_id}")

    log "📨 Sending ${label} (${RUN_MODE_UPPER}, ${#attachment_specs[@]} attachment(s))..."
    telegram_api_call "sendRichMessage" "$RESPONSE_FILE" "$label" "${send_args[@]}" \
        || error "${label} failed"

    message_id="$(jq -r '.result.message_id // empty' <<< "$TG_RESPONSE")"
    log "Sent ✅ ${label} (message_id=${message_id})"
}

assert_all_variants_staged() {
    local missing
    [ -n "${EXPECTED_MATRIX_JSON:-}" ] || return 0
    missing="$(jq -nr \
        --argjson expected "$EXPECTED_MATRIX_JSON" \
        --slurpfile staged <(for zip in "$STAGE_DIR"/*.zip; do unzip -p "$zip" luminaire.json; done) '
        ($staged | map(.variant)) as $have
        | $expected.include
        | map(if (.susfs == true and .kernel_variant != "VANILLA") then "\(.kernel_variant)_SUSFS" else .kernel_variant end)
        | map(select(. as $key | ($have | index($key)) == null))
        | join(", ")')"
    [ -z "$missing" ] || error "Aborting channel post: variant(s) selected but not staged — ${missing}. Check the Start-Build job for that variant before re-running Release."
}

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "Skipping post: TELEGRAM_BOT_TOKEN not set"
    exit 0
fi
if [ ! -d "$STAGE_DIR" ] || [ -z "$(find "$STAGE_DIR" -name '*.zip' -print -quit)" ]; then
    warn "Skipping post: no staged variants in ${STAGE_DIR}"
    exit 0
fi

RUN_MODE_UPPER="${RUN_MODE^^}"
case "$RUN_MODE_UPPER" in
    BUILD|RELEASE) ;;
    *) error "Telegram: unknown RUN_MODE '${RUN_MODE:-}' — expected Build or Release" ;;
esac

trap cleanup EXIT

if [ "${DELIVERY_TARGET:-Community}" = "Private" ]; then
    [ -n "${TELEGRAM_PERSONAL_CHAT_ID:-}" ] || error "DELIVERY_TARGET=Private but TELEGRAM_PERSONAL_CHAT_ID not set"
    PRIVATE_BANNER=0
    [ "$RUN_MODE_UPPER" = "RELEASE" ] && PRIVATE_BANNER=1
    send_post "$TELEGRAM_PERSONAL_CHAT_ID" "" "$PRIVATE_BANNER" "Private post"
    exit 0
fi

if [ "$RUN_MODE_UPPER" = "RELEASE" ]; then
    [ -n "${TELEGRAM_CHANNEL_ID:-}" ] || error "TELEGRAM_CHANNEL_ID not set"
    assert_all_variants_staged
    send_post "$TELEGRAM_CHANNEL_ID" "" 1 "Channel post"
    exit 0
fi

GROUP_THREAD_ID="${TELEGRAM_THREAD_ID_BUILD_BY_VERSION[$KERNEL_VERSION]:-}"
[ -n "${TELEGRAM_CHAT_ID:-}" ] || error "TELEGRAM_CHAT_ID not set"
[ -n "$GROUP_THREAD_ID" ] || error "No thread id configured for KERNEL_VERSION=${KERNEL_VERSION:-}"

send_post "$TELEGRAM_CHAT_ID" "$GROUP_THREAD_ID" 0 "Group post"
