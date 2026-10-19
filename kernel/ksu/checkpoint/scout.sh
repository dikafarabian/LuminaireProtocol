#!/usr/bin/env bash

# ======================================================
# 🔭 CHECKPOINT — Scout
# ======================================================
# Resolves pinned vs candidate refs for the KSU fork and SuSFS

set -eo pipefail

ROOT_DIR="${ROOT_DIR:-$GITHUB_WORKSPACE}"
source "${ROOT_DIR}/functions.sh"
source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"

[ -n "${KERNEL_VERSION:-}" ] || error "scout: KERNEL_VERSION not set"
MANIFEST="${ROOT_DIR}/kernel/ksu/manifests/$(resolve_android_version)-${KERNEL_VERSION}.json"

if [ ! -f "$MANIFEST" ]; then
    warn "scout: no manifest yet for kernel ${KERNEL_VERSION} — treating as no pins/candidates yet"
    MANIFEST="$(mktemp)"
    echo '{}' > "$MANIFEST"
fi

latest_sha_or_empty() {
    local label="$1" url="$2" jq_filter="$3"
    local body_file http_code curl_exit sha auth_args=()

    case "$url" in
        https://api.github.com/*) auth_args=("${GITHUB_AUTH_ARGS[@]}") ;;
    esac

    body_file="$(mktemp)"
    if http_code=$(curl -sL -o "$body_file" -w '%{http_code}' --max-time 20 \
            "${auth_args[@]}" "$url"); then
        curl_exit=0
    else
        curl_exit=$?
    fi

    if [ "$curl_exit" -ne 0 ] || [ "$http_code" != "200" ]; then
        warn "scout: couldn't reach upstream for ${label} (curl exit ${curl_exit}, HTTP ${http_code:-000}) — using pinned ref"
        rm -f "$body_file"
        echo ""
        return 0
    fi

    sha=$(jq -r "$jq_filter" "$body_file" 2>/dev/null)
    rm -f "$body_file"
    if [ -z "$sha" ] || [ "$sha" = "null" ]; then
        warn "scout: couldn't parse latest ${label} commit — using pinned ref"
        echo ""
        return 0
    fi
    echo "$sha"
}

resolve_component() {
    local key="$1" prefix="$2" latest="$3"
    local pinned skip_list is_skipped ref candidate

    pinned=$(jq -r ".${key}.pin // \"\"" "$MANIFEST")
    skip_list=$(jq -c ".${key}.skip // []" "$MANIFEST")

    if [ "${RUN_MODE^^}" = "RELEASE" ]; then
        [ -n "$pinned" ] || error "scout: RUN_MODE=Release but no ${key} pin exists yet — run a Build first."
        ref="$pinned"; candidate="false"
        log "${prefix}: Release mode — pinned to ${ref:0:12} (no upstream check)"
    elif [ -z "$latest" ]; then
        ref="$pinned"; candidate="false"
        log "${prefix}: no candidate available — using pin ${pinned:0:12}"
    elif [ "$latest" = "$pinned" ]; then
        ref="$pinned"; candidate="false"
        log "${prefix}: up to date at ${pinned:0:12}"
    else
        is_skipped=$(echo "$skip_list" | jq --arg sha "$latest" 'any(. == $sha)')
        if [ "$is_skipped" = "true" ]; then
            if [ -n "$pinned" ]; then
                ref="$pinned"; candidate="false"
                warn "${prefix}: latest upstream ${latest:0:12} is on the skip list — keeping pin ${pinned:0:12}"
            else
                ref="$latest"; candidate="true"
                warn "${prefix}: latest upstream ${latest:0:12} is on the skip list and no pin exists — retrying it as a last-resort candidate to break the deadlock"
            fi
        else
            ref="$latest"; candidate="true"
            log "${prefix}: new candidate ${latest:0:12} (pin: ${pinned:-none}) — will verify this build"
        fi
    fi

    github_env "${prefix}_REF" "$ref"
    github_env "CANDIDATE_${prefix}" "$candidate"
}

GITHUB_API="https://api.github.com/repos"

susfs_commits_api() {
    local project="${MIRROR_SOURCE_URL[$1]%.git}"
    project="${project#https://gitlab.com/}"
    echo "https://gitlab.com/api/v4/projects/${project//\//%2F}/repository/commits"
}

track_commit() {
    local key="$1" prefix="$2" label="$3" repo="$4" branch="$5" latest
    latest="$(latest_sha_or_empty "$label" "${GITHUB_API}/${repo}/commits/${branch}" '.sha')"
    resolve_component "$key" "$prefix" "$latest"
}

track_release() {
    local key="$1" prefix="$2" label="$3" repo="$4" tag latest=""
    tag="$(latest_sha_or_empty "${label} release" "${GITHUB_API}/${repo}/releases/latest" '.tag_name')"
    if [ -n "$tag" ]; then
        latest="$(latest_sha_or_empty "$label" "${GITHUB_API}/${repo}/commits/${tag}" '.sha')"
    fi
    resolve_component "$key" "$prefix" "$latest"
}

track_susfs() {
    local key="$1" prefix="$2" label="$3" branch_suffix="${4:-}" branch latest
    branch="gki-$(resolve_android_version)-${KERNEL_VERSION}${branch_suffix}"
    latest="$(latest_sha_or_empty "$label" "$(susfs_commits_api "$key")/${branch}" '.id')"
    resolve_component "$key" "$prefix" "$latest"
}

case "$KERNEL_VARIANT" in
    KSU)
        track_commit ksu KSU "KernelSU (official)" tiann/KernelSU main
        if susfs_active; then
            track_susfs susfs_ksu SUSFS_KSU "SuSFS (KernelSU official pairing)"
        fi
        ;;
    KOWSU)
        track_commit kowsu KOWSU "KowSU (master)" KOWX712/KernelSU master
        if susfs_active; then
            track_susfs susfs_kowsu SUSFS_KOWSU "SuSFS (KowSU pairing)"
        fi
        ;;
    KSUNEXT)
        track_commit ksunext KSUNEXT "KernelSU-Next (pershoot dev-susfs)" pershoot/KernelSU-Next dev-susfs
        if susfs_active; then
            track_susfs susfs_ksunext SUSFS_KSUNEXT "SuSFS (KSU-Next pairing, pershoot)" -dev
        fi
        ;;
    SUKISU)
        if susfs_active; then
            track_commit sukisu_builtin SUKISU_BUILTIN "SukiSU-Ultra (builtin)" SukiSU-Ultra/SukiSU-Ultra builtin
            track_susfs susfs_sukisu SUSFS_SUKISU "SuSFS (SukiSU pairing)"
        else
            track_release sukisu SUKISU "SukiSU-Ultra" SukiSU-Ultra/SukiSU-Ultra
        fi
        ;;
    BAKASU)
        track_commit bakasu BAKASU "BakaSU" Baka-SU/BakaSU main
        if susfs_active; then
            track_susfs susfs_bakasu SUSFS_BAKASU "SuSFS (BakaSU pairing)"
        fi
        ;;
    VANILLA)
        log "scout: VANILLA — nothing to track"
        ;;
esac
