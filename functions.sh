#!/usr/bin/env bash

# ======================================================
# 🧩 FUNCTIONS — Shared Helpers
# ======================================================
# Logging, retry, stage markers, version and branch resolvers

COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

log() {
  echo -e "${COLOR_CYAN}[LOG]${COLOR_RESET} $*" >&2
}

warn() {
  echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

error() {
  echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
  exit 1
}

on_err() {
    local rc="$1" file="$2" line="$3" cmd="$4"
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} ${file#"${ROOT_DIR}/"}:${line} — ${cmd} (exit ${rc})" >&2
}

enable_error_trace() {
    set -E
    trap 'on_err $? "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND"' ERR
}

run_quiet() {
    local logfile rc=0
    logfile="$(mktemp)"
    "$@" > "$logfile" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
        rm -f "$logfile"
        return 0
    fi
    echo -e "${COLOR_YELLOW}---- command output (last 50 lines) ----${COLOR_RESET}"
    tail -n 50 "$logfile"
    echo -e "${COLOR_YELLOW}-----------------------------------------${COLOR_RESET}"
    rm -f "$logfile"
    return "$rc"
}

github_env() {
    [ -n "${GITHUB_ENV:-}" ] || return 0
    echo "$1=$2" >> "$GITHUB_ENV"
}

github_path() {
    [ -n "${GITHUB_PATH:-}" ] || return 0
    echo "$1" >> "$GITHUB_PATH"
}

mark_stage_ok() {
    github_env "$1" true
}

join_csv() {
    local IFS=,
    echo "$*"
}

write_dry_run_image() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    echo "Luminaire Protocol — dry-run placeholder, not a real kernel image" > "$path"
    log "🧪 DRY RUN — wrote placeholder image to ${path} (compile skipped)"
}

resolve_android_version() {
    case "${KERNEL_VERSION}" in
        "5.10") echo "android12" ;;
        "5.15") echo "android13" ;;
        "6.1")  echo "android14" ;;
        "6.6")  echo "android15" ;;
        "6.12") echo "android16" ;;
        *) error "Unknown kernel version: ${KERNEL_VERSION}" ;;
    esac
}

resolve_kernel_branch() {
    local base
    base="$(resolve_android_version)-${KERNEL_VERSION}"
    case "${KERNEL_BRANCH_OVERRIDE}" in
        ""|"base") echo "${base}" ;;
        *) echo "${base}-${KERNEL_BRANCH_OVERRIDE}" ;;
    esac
}

KERNEL_SOURCE_OWNER="chainonyourdoor"

kernel_source_repo() {
    echo "LuminaireKernel-${KERNEL_VERSION}"
}

kernel_source_url() {
    echo "https://github.com/${KERNEL_SOURCE_OWNER}/$(kernel_source_repo)"
}

verify_kernel_branch() {
    git ls-remote --exit-code --heads "$(kernel_source_url)" "refs/heads/$1" >/dev/null 2>&1 \
        || error "Kernel branch $1 not found in $(kernel_source_repo)"
}

run_setup() {
    echo "::group::📦 Setup"
    for script in "${ROOT_DIR}/setup/"*.sh; do
        source "$script"
    done
    echo "::endgroup::"
}

run_step() {
    local emoji="$1" label="$2" script="$3" missing_msg="$4"
    [ -f "$script" ] || error "$missing_msg"
    echo "::group::${emoji} ${label}"
    source "$script"
    echo "::endgroup::"
}

wait_for_apt() {
    if [ -n "${APT_PID:-}" ]; then
        log "Waiting for background apt install (PID ${APT_PID})..."
        local waited=0 max_wait=600
        while kill -0 "$APT_PID" 2>/dev/null; do
            sleep 5
            waited=$((waited + 5))
            if [ "$waited" -ge "$max_wait" ]; then
                sudo kill -9 "$APT_PID" 2>/dev/null || true
                warn "apt install log tail (${APT_LOG:-/tmp/luminaire-apt-install.log}):"
                tail -n 50 "${APT_LOG:-/tmp/luminaire-apt-install.log}" 2>/dev/null || true
                error "Background apt install timed out after ${max_wait}s — killed PID ${APT_PID}"
            fi
        done
        if wait "$APT_PID"; then
            mkdir -p ~/.apt-cache
            sudo cp /var/cache/apt/archives/*.deb ~/.apt-cache/ 2>/dev/null || true
            log "Dependencies installed ✅"
        else
            warn "apt install log tail (${APT_LOG:-/tmp/luminaire-apt-install.log}):"
            tail -n 50 "${APT_LOG:-/tmp/luminaire-apt-install.log}" 2>/dev/null || true
            error "Background apt install failed!"
        fi
    fi
}

retry() {
    local max_attempts="$1"; shift
    local attempt=1 delay=5 rc
    while true; do
        rc=0
        "$@" || rc=$?
        if [ "$rc" -eq 0 ]; then
            return 0
        fi
        if [ "$attempt" -ge "$max_attempts" ]; then
            return "$rc"
        fi
        warn "Attempt ${attempt}/${max_attempts} failed — retrying in ${delay}s..."
        sleep "$delay"
        delay=$(( delay * 2 ))
        attempt=$(( attempt + 1 ))
    done
}

GITHUB_AUTH_ARGS=()
if [ -n "${PERSONAL_TOKEN:-}" ]; then
    GITHUB_AUTH_ARGS=(-H "Authorization: Bearer ${PERSONAL_TOKEN}")
fi

github_api() {
    retry 3 curl -fsSL --connect-timeout 15 --max-time 30 "${GITHUB_AUTH_ARGS[@]}" "$1"
}

github_commit_count() {
    local repo="$1" branch="$2"
    curl -sI --connect-timeout 15 --max-time 30 "${GITHUB_AUTH_ARGS[@]}" \
        "https://api.github.com/repos/${repo}/commits?sha=${branch}&per_page=1" 2>/dev/null \
        | sed -n 's/^[Ll]ink:.*page=\([0-9]*\)>; rel="last".*/\1/p'
}

github_latest_release_tag() {
    github_api "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty'
}

latest_release_asset_url() {
    local repo="$1" suffix="$2"
    github_api "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -r --arg suffix "$suffix" '[.assets[]? | select(.name | endswith($suffix)) | .browser_download_url][0] // empty'
}

fetch() {
    curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 "$@"
}

patch_is_applied() {
    local patch_file="$1" dir="$2"
    shift 2
    patch -p1 "$@" --dry-run --reverse -d "$dir" < "$patch_file" > /dev/null 2>&1
}

apply_patch() {
    local label="$1" patch_file="$2" dir="$3" output
    shift 3
    [ -f "$patch_file" ] || error "${label}: patch file not found: ${patch_file}"

    if patch_is_applied "$patch_file" "$dir" "$@"; then
        log "${label}: patch already applied, skipping."
        return 0
    fi

    if ! output="$(patch -p1 "$@" --no-backup-if-mismatch --forward --dry-run -d "$dir" < "$patch_file" 2>&1)"; then
        tail -n 40 <<< "$output"
        error "${label}: patch does not apply cleanly — conflict or unsupported source!"
    fi

    output="$(patch -p1 "$@" --no-backup-if-mismatch --forward -d "$dir" < "$patch_file" 2>&1)" \
        || { echo "$output"; error "${label}: patch apply failed!"; }
    echo "$output"
    if grep -q "with fuzz" <<< "$output"; then
        warn "${label}: some hunks applied with fuzz — context drifted, verify hunk placement"
    fi
    log "${label}: patch applied ✅"
}

apply_remote_patch() {
    local label="$1" url="$2" dir="$3" tmp
    shift 3
    tmp="$(mktemp)"
    fetch -o "$tmp" "$url" || { rm -f "$tmp"; error "${label}: failed to download patch!"; }
    [ -s "$tmp" ] || { rm -f "$tmp"; error "${label}: downloaded patch is empty!"; }
    apply_patch "$label" "$tmp" "$dir" "$@"
    rm -f "$tmp"
}

run_upstream_setup() {
    local label="$1" url="$2" ref="${3:-}" script
    script="$(fetch "$url")" || error "${label}: failed to download setup.sh!"
    [ -n "$script" ] || error "${label}: setup.sh is empty!"
    grep -q "^#!" <<< "$script" || error "${label}: setup.sh looks invalid (no shebang)!"
    if [ -n "$ref" ]; then
        log "Pinning ${label} to ${ref}"
        printf '%s\n' "$script" | bash -s -- "$ref" || error "${label}: setup.sh failed!"
    else
        printf '%s\n' "$script" | bash || error "${label}: setup.sh failed!"
    fi
}

gki_defconfig_enable() {
    local defconfig="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" option
    for option in "$@"; do
        grep -q "^${option}=y" "$defconfig" || echo "${option}=y" >> "$defconfig"
    done
}

ksu_uapi_version() {
    grep -oP 'KERNEL_SU_UAPI_VERSION\s*=\s*\K[0-9]+' "$1/uapi/supercall.h" 2>/dev/null || true
}

format_ksu_version() {
    local tag="$1" code="$2" uapi="${3:-}"
    if [ -n "$uapi" ]; then
        echo "${tag} (${code}/${uapi})"
    else
        echo "${tag} (${code})"
    fi
}

cache_freshness_note() {
    if [ "${CACHE_REFRESHED:-false}" = "true" ]; then
        echo "pre-warmed fresh by Prepare Arsenal this run"
    else
        echo "existing cache, no refresh requested — set 'Update Arsenal' to force"
    fi
}

verify_pinned_ref() {
    local label="$1" dir="$2" expected="$3" actual
    [[ "$expected" =~ ^[0-9a-f]{7,40}$ ]] || return 0
    actual="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "")"
    if [ -z "$actual" ] || [[ "$actual" != "$expected"* ]]; then
        error "${label}: pinned ref ${expected} did not check out (HEAD is ${actual:-unknown}) — pin is likely stale/unreachable upstream, needs re-pin in the manifest"
    fi
    log "${label}: pin verified at ${actual:0:12} ✅"
}

susfs_active() {
    [ "${SUSFS_ENABLED:-false}" = "true" ] && [ "${KERNEL_VARIANT:-}" != "VANILLA" ]
}

variant_label() {
    if susfs_active; then
        echo "${KERNEL_VARIANT}+SUSFS"
    else
        echo "${KERNEL_VARIANT}"
    fi
}

variant_key() {
    if susfs_active; then
        echo "${KERNEL_VARIANT}_SUSFS"
    else
        echo "${KERNEL_VARIANT}"
    fi
}

variant_display_name() {
    case "$1" in
        KSU)     echo "KernelSU" ;;
        KOWSU)   echo "KowSU" ;;
        KSUNEXT) echo "KernelSU-Next" ;;
        SUKISU)  echo "SukiSU-Ultra" ;;
        BAKASU)  echo "BakaSU" ;;
        VANILLA) echo "Vanilla" ;;
        *)       echo "$1" ;;
    esac
}

susfs_version_tag() {
    sed -n 's/^#define SUSFS_VERSION "\(.*\)"/\1/p' "${KERNEL_SRC:-}/include/linux/susfs.h" 2>/dev/null | head -n 1 || true
}

variant_summary() {
    local version_var="${KERNEL_VARIANT}_VERSION_DISPLAY" susfs_tag summary
    summary="$(variant_display_name "$KERNEL_VARIANT")${!version_var:+ ${!version_var}}"
    if susfs_active; then
        susfs_tag="$(susfs_version_tag)"
        summary+=" · SuSFS${susfs_tag:+ ${susfs_tag}}"
    fi
    echo "$summary"
}

mode_emoji() {
    case "$1" in
        "Dry Run")  echo "🧪" ;;
        "Warm Run") echo "🔥" ;;
        "Build")    echo "🔬" ;;
        "Release") echo "🚀" ;;
        *)         echo "❓" ;;
    esac
}
