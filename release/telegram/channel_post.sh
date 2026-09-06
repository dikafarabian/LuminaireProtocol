#!/usr/bin/env bash

TELEGRAM_DIR="${LUMINAIRE_PATCH_DIR}/release/telegram"
RICH_BUILDER="${TELEGRAM_DIR}/rich_message.py"
BANNER_DIR="${TELEGRAM_DIR}"

# shellcheck source=functions.sh
source "${LUMINAIRE_PATCH_DIR}/functions.sh"
# shellcheck source=release/telegram/config.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/config.sh"
# shellcheck source=release/telegram/common.sh
source "${LUMINAIRE_PATCH_DIR}/release/telegram/common.sh"

TELEGRAM_API_TIMEOUT="${TELEGRAM_API_TIMEOUT:-60}"
TELEGRAM_MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-3}"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    warn "Skipping channel post: TELEGRAM_BOT_TOKEN not set"
    exit 0
fi
if [ -z "${TELEGRAM_CHANNEL_ID:-}" ]; then
    warn "Skipping channel post: TELEGRAM_CHANNEL_ID not set in config.sh"
    exit 0
fi

BANNER_PATH=""
for ext in jpg jpeg png; do
    candidate="${BANNER_DIR}/banner.${ext}"
    if [ -f "$candidate" ]; then
        BANNER_PATH="$candidate"
        break
    fi
done

if [ -z "$BANNER_PATH" ]; then
    warn "Skipping channel post: no banner found in ${BANNER_DIR}"
    exit 0
fi

LINKS_DIR="${LINKS_DIR:-/tmp/variant-links}"

if [ ! -d "$LINKS_DIR" ]; then
    warn "Skipping channel post: LINKS_DIR not found (${LINKS_DIR})"
    exit 0
fi

LINKS_PARSED=$(python3 -c "
import json, glob, sys
links_dir = '${LINKS_DIR}'
result = {}
versions = {}
linux_ver = ''
kernel_version = ''
compiler_string = ''
lto_mode = ''
addons = ''
addon_order = ''
skipped_addons = ''
applied_tuning = ''
skipped_tuning = ''
for f in sorted(glob.glob(links_dir + '/*.json')):
    try:
        data = json.load(open(f))
        v = data.get('variant',''); l = data.get('link','')
        if v and l:
            result[v] = l
        kv = data.get('ksu_version','')
        if v and kv:
            versions[v] = kv
        if not linux_ver: linux_ver = data.get('linux_ver','')
        if not kernel_version: kernel_version = data.get('kernel_version','')
        if not compiler_string: compiler_string = data.get('compiler_string','')
        if not lto_mode: lto_mode = data.get('lto_mode','')
        if not addons: addons = data.get('addons','')
        if not addon_order: addon_order = data.get('addon_order','')
        if not skipped_addons: skipped_addons = data.get('skipped_addons','')
        if not applied_tuning: applied_tuning = data.get('applied_tuning','')
        if not skipped_tuning: skipped_tuning = data.get('skipped_tuning','')
    except Exception as e:
        print('[warn] ' + str(e), file=sys.stderr)
print(json.dumps({'links':result,'versions':versions,'linux_ver':linux_ver,'kernel_version':kernel_version,'compiler_string':compiler_string,'lto_mode':lto_mode,'addons':addons,'addon_order':addon_order,'skipped_addons':skipped_addons,'applied_tuning':applied_tuning,'skipped_tuning':skipped_tuning}))
")

VARIANT_LINKS_JSON=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['links']))")
VARIANT_VERSIONS_JSON=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['versions']))")
LINUX_VER=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['linux_ver'])")
KERNEL_VERSION=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['kernel_version'])")
COMPILER_STRING=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['compiler_string'])")
LTO_MODE=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['lto_mode'])")
ADDONS=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['addons'])")
ADDON_ORDER=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['addon_order'])")
SKIPPED_ADDONS=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['skipped_addons'])")
APPLIED_TUNING=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['applied_tuning'])")
SKIPPED_TUNING=$(echo "$LINKS_PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin)['skipped_tuning'])")
export LINUX_VER KERNEL_VERSION COMPILER_STRING LTO_MODE ADDONS ADDON_ORDER SKIPPED_ADDONS APPLIED_TUNING SKIPPED_TUNING

if [ "$VARIANT_LINKS_JSON" = "{}" ] || [ -z "$VARIANT_LINKS_JSON" ]; then
    warn "Skipping channel post: no valid variant links found"
    exit 0
fi

log "Variant links: $VARIANT_LINKS_JSON"
log "Linux version: $LINUX_VER | Kernel: $KERNEL_VERSION"

MISSING_VARIANTS_JSON=$(VARIANT_LINKS_JSON="$VARIANT_LINKS_JSON" python3 -c "
import json, os
matrix_json = os.environ.get('EXPECTED_MATRIX_JSON', '')
links = json.loads(os.environ.get('VARIANT_LINKS_JSON', '') or '{}')
missing = []
if matrix_json:
    try:
        matrix = json.loads(matrix_json)
        for entry in matrix.get('include', []):
            variant = entry.get('kernel_variant', '')
            susfs = entry.get('susfs', False)
            key = variant
            if susfs and variant != 'VANILLA':
                key = f'{variant}_SUSFS'
            if key and key not in links:
                missing.append(key)
    except Exception as e:
        print(f'[warn] {e}', file=__import__('sys').stderr)
print(json.dumps(missing))
")

if [ "$MISSING_VARIANTS_JSON" != "[]" ]; then
    error "Aborting channel post: variant(s) selected but missing a download link — ${MISSING_VARIANTS_JSON}. Check the Start-Build job for that variant before re-running Release."
fi

RICH_PAYLOAD="/tmp/channel_post_rich.json"

LINUX_VER="${LINUX_VER:-N/A}" \
    KERNEL_VERSION="${KERNEL_VERSION:-}" \
    ADDONS="${ADDONS:-}" \
    ADDON_ORDER="${ADDON_ORDER:-}" \
    SKIPPED_ADDONS="${SKIPPED_ADDONS:-}" \
    APPLIED_TUNING="${APPLIED_TUNING:-}" \
    SKIPPED_TUNING="${SKIPPED_TUNING:-}" \
    COMPILER_STRING="${COMPILER_STRING:-}" \
    LTO_MODE="${LTO_MODE:-}" \
    CHANGELOG="${CHANGELOG:-}" \
    TELEGRAM_GROUP="${TELEGRAM_GROUP:-}" \
    GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}" \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" \
    VARIANT_LINKS_JSON="$VARIANT_LINKS_JSON" \
    VARIANT_VERSIONS_JSON="$VARIANT_VERSIONS_JSON" \
    RICH_HAS_BANNER="1" \
    python3 "$RICH_BUILDER" "$RICH_PAYLOAD" \
    || error "Rich message builder failed"

log "📸 Sending channel post..."
if telegram_api_call "sendRichMessage" /tmp/tg_channel_response.json "Channel send" \
        -F "chat_id=${TELEGRAM_CHANNEL_ID}" \
        -F "rich_message=<${RICH_PAYLOAD}" \
        -F "banner_file=@${BANNER_PATH}"; then
    log "Channel post sent ✅"
else
    rm -f "$RICH_PAYLOAD" /tmp/tg_channel_response.json
    error "Channel post failed"
fi

rm -f "$RICH_PAYLOAD" /tmp/tg_channel_response.json
