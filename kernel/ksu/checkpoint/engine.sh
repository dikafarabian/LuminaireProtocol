#!/usr/bin/env bash

# ======================================================
# 🚦 CHECKPOINT — Engine
# ======================================================
# Syncs pinned refs to their mirrors, promotes verified candidates, opens skip proposals as pull requests, and prunes finished proposal branches

set -eo pipefail

ROOT_DIR="${ROOT_DIR:-$GITHUB_WORKSPACE}"
source "${ROOT_DIR}/functions.sh"
source "${ROOT_DIR}/kernel/ksu/checkpoint/mirrors.sh"
cd "$ROOT_DIR"

BUILD_OUTCOME="$1"
shift
COMPONENTS=("$@")

[ -n "${KERNEL_VERSION:-}" ] || error "checkpoint: KERNEL_VERSION not set"
MANIFEST_REL="kernel/ksu/manifests/$(resolve_android_version)-${KERNEL_VERSION}.json"
MANIFEST="${ROOT_DIR}/${MANIFEST_REL}"

MIRROR_LABEL="$(resolve_android_version)-${KERNEL_VERSION}"

init_remote() {
    [ -n "${PERSONAL_TOKEN:-}" ] || error "checkpoint: PERSONAL_TOKEN not set — cannot push to ${GITHUB_REPOSITORY}"

    git config --global user.name  "luminaire-bot"
    git config --global user.email "luminaire-bot@users.noreply.github.com"

    REMOTE="https://x-access-token:${PERSONAL_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
}

apply_and_push() {
    local jq_patch="$1" commit_msg="$2"
    local attempt=1 max_attempts=5

    init_remote

    while [ "$attempt" -le "$max_attempts" ]; do
        run_quiet git fetch "$REMOTE" main
        git reset -q --hard FETCH_HEAD

        mkdir -p "$(dirname "$MANIFEST")"
        [ -f "$MANIFEST" ] || echo '{}' > "$MANIFEST"

        jq "$jq_patch" "$MANIFEST" > "${MANIFEST}.tmp" \
            || error "checkpoint: jq patch failed against ${MANIFEST_REL} — patch: ${jq_patch}"
        mv "${MANIFEST}.tmp" "$MANIFEST"

        (
            git add "$MANIFEST_REL"
            git commit -q -m "$commit_msg" 2>/dev/null || { echo "nothing to commit"; exit 0; }
            git push "$REMOTE" "HEAD:main"
        ) && return 0

        warn "checkpoint: push conflict (attempt ${attempt}/${max_attempts}) — retrying..."
        attempt=$(( attempt + 1 ))
        sleep $(( RANDOM % 5 + 2 ))
    done

    error "checkpoint: failed to push manifest update after ${max_attempts} attempts"
}

is_candidate() {
    local flag="CANDIDATE_${1^^}"
    [ "${!flag:-false}" = "true" ]
}

candidate_ref() {
    local ref_var="${1^^}_REF"
    echo "${!ref_var}"
}

component_label() {
    local key="$1" fork
    case "$key" in
        susfs_*)
            fork="${key#susfs_}"
            echo "SuSFS ($(variant_display_name "${fork^^}"))"
            ;;
        sukisu_builtin)     echo "$(variant_display_name SUKISU) (builtin)" ;;
        *)                  variant_display_name "${key^^}" ;;
    esac
}

commit_url() {
    local key="$1" ref="$2" base="${MIRROR_SOURCE_URL[$1]:-}"
    [ -n "$base" ] || return 0
    base="${base%.git}"
    case "$base" in
        *gitlab.com*) echo "${base}/-/commit/${ref}" ;;
        *)            echo "${base}/commit/${ref}" ;;
    esac
}

proposal_prefix() {
    echo "skip/${1}-${KERNEL_VERSION}-"
}

open_proposals() {
    gh pr list --repo "$GITHUB_REPOSITORY" --state open --limit 100 --json number,headRefName \
        --jq ".[] | select(.headRefName | startswith(\"$(proposal_prefix "$1")\")) | \"\(.number) \(.headRefName)\"" 2>/dev/null || true
}

close_proposals() {
    local key="$1" comment="$2" keep_branch="${3:-}" number branch
    while read -r number branch; do
        [ -n "$number" ] || continue
        [ "$branch" = "$keep_branch" ] && continue
        gh pr close "$number" --repo "$GITHUB_REPOSITORY" --delete-branch --comment "$comment" \
            || warn "checkpoint: couldn't close proposal #${number}"
    done <<< "$(open_proposals "$key")"
}

prune_proposal_branches() {
    local open_branches finished_branches branch
    open_branches="$(gh pr list --repo "$GITHUB_REPOSITORY" --state open --limit 100 --json headRefName --jq '.[].headRefName' 2>/dev/null || true)"
    finished_branches="$(gh pr list --repo "$GITHUB_REPOSITORY" --state all --limit 200 --json headRefName,state --jq '.[] | select(.state != "OPEN") | .headRefName' 2>/dev/null || true)"
    while read -r branch; do
        [ -n "$branch" ] || continue
        grep -qxF "$branch" <<< "$open_branches" && continue
        grep -qxF "$branch" <<< "$finished_branches" || continue
        if ! git push -q "$REMOTE" --delete "$branch" 2>/dev/null; then
            git ls-remote --exit-code --heads "$REMOTE" "$branch" > /dev/null 2>&1 \
                && warn "checkpoint: couldn't delete stale branch ${branch}"
        fi
    done <<< "$(git ls-remote --heads "$REMOTE" 'refs/heads/skip/*' | awk '{sub("refs/heads/", "", $2); print $2}')"
}

proposal_stage_label() {
    if [ "${CHECKPOINT_VARIANT_OK:-false}" = "true" ]; then
        echo "kernel compile"
    else
        echo "root solution / SuSFS setup"
    fi
}

push_proposal_branch() {
    local key="$1" ref="$2" branch="$3" tree
    init_remote
    run_quiet git fetch "$REMOTE" main
    tree="$(mktemp -d)"
    git worktree add -q --detach "$tree" FETCH_HEAD
    if ! (
        cd "$tree" \
        && git checkout -q -b "$branch" \
        && jq --arg ref "$ref" ".${key}.skip |= (. + [\$ref] | unique)" "$MANIFEST_REL" > "${MANIFEST_REL}.tmp" \
        && mv "${MANIFEST_REL}.tmp" "$MANIFEST_REL" \
        && git add "$MANIFEST_REL" \
        && git commit -q -m "CHECKPOINT: skip $(component_label "$key") ${ref:0:7} (${KERNEL_VERSION})" \
        && git push -q --force "$REMOTE" "$branch"
    ); then
        git worktree remove --force "$tree"
        return 1
    fi
    git worktree remove --force "$tree"
}

open_proposal_pr() {
    local key="$1" ref="$2" branch="$3" others="$4"
    local label run_url commit_link pin pin_display body

    label="$(component_label "$key")"
    run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    commit_link="$(commit_url "$key" "$ref")"
    pin="$(jq -r ".${key}.pin // \"\"" "$MANIFEST")"
    pin_display="none"
    [ -z "$pin" ] || pin_display="\`${pin:0:7}\`"

    body="**${label}** \`${ref:0:7}\` failed to build on ${KERNEL_VERSION} ($(proposal_stage_label)).

- Current pin: ${pin_display}"
    [ -z "$commit_link" ] || body="${body}
- Commit: ${commit_link}"
    body="${body}
- Run: [${GITHUB_RUN_ID}](${run_url})

- Merge = skip this commit in future builds.
- Close = leave it, it will be retried."
    [ -z "$pin" ] || body="${body}

The pin stays on \`${pin:0:7}\` either way."

    if [ -n "$others" ]; then
        body="${body}

Also tested in this run (cause could be any):
${others%$'\n'}"
    fi

    gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" \
        --title "Skip ${label} ${ref:0:7} (${KERNEL_VERSION})" --body "$body" \
        || warn "checkpoint: couldn't open proposal for ${key}"
}

file_proposal() {
    local key="$1" ref="$2" others="$3"
    local branch existing
    branch="$(proposal_prefix "$key")${ref:0:12}"

    existing="$(open_proposals "$key")"
    if [[ $'\n'"${existing}"$'\n' == *" ${branch}"$'\n'* ]]; then
        log "checkpoint: proposal for ${key} ${ref:0:12} is already open"
        return 0
    fi
    close_proposals "$key" "Superseded by \`${ref:0:7}\`." "$branch"

    if ! push_proposal_branch "$key" "$ref" "$branch"; then
        warn "checkpoint: couldn't push proposal branch for ${key}"
        return 0
    fi
    open_proposal_pr "$key" "$ref" "$branch" "$others"
}

propose_skip() {
    local key="$1" ref="$2" other_key other_ref others=""

    for other_key in "${COMPONENTS[@]}"; do
        [ "$other_key" = "$key" ] && continue
        is_candidate "$other_key" || continue
        other_ref="$(candidate_ref "$other_key")"
        others="${others}- $(component_label "$other_key") \`${other_ref:0:7}\`
"
    done

    file_proposal "$key" "$ref" "$others"
}

sync_mirrors() {
    local key pinned_ref
    for key in "${COMPONENTS[@]}"; do
        pinned_ref="$(jq -r ".${key}.pin // \"\"" "$MANIFEST" 2>/dev/null || true)"
        [ -n "$pinned_ref" ] || continue
        mirror_sync "$key" "$pinned_ref" "$MIRROR_LABEL"
    done
}

any_candidate_used() {
    local key
    for key in "${COMPONENTS[@]}"; do
        is_candidate "$key" && return 0
    done
    return 1
}

failure_stage() {
    if [ "${CHECKPOINT_PRE_VARIANT_OK:-false}" != "true" ]; then
        echo "setup"
    elif [ "${CHECKPOINT_VARIANT_OK:-false}" = "true" ] && [ "${CHECKPOINT_ADDONS_OK:-false}" != "true" ]; then
        echo "core_addons"
    elif [ "${CHECKPOINT_ADDONS_OK:-false}" = "true" ] && [ "${CHECKPOINT_BUILD_OK:-false}" = "true" ]; then
        echo "release"
    else
        echo "candidate"
    fi
}

promote_candidate() {
    local key="$1" ref="$2" partner_key partner_reset="" previous commit_msg

    previous="$(jq -r ".${key}.pin // \"\"" "$MANIFEST")"
    log "checkpoint: promoting ${key} pin to ${ref:0:12} (kernel ${KERNEL_VERSION})"
    for partner_key in "${COMPONENTS[@]}"; do
        [ "$partner_key" = "$key" ] && continue
        partner_reset="${partner_reset} | if .${partner_key} then .${partner_key}.skip = [] else . end"
    done
    if [ -n "$previous" ]; then
        commit_msg="CHECKPOINT: pin $(component_label "$key") ${previous:0:7} -> ${ref:0:7} (${KERNEL_VERSION})"
    else
        commit_msg="CHECKPOINT: pin $(component_label "$key") ${ref:0:7} (${KERNEL_VERSION})"
    fi
    apply_and_push ".${key}.pin = \"${ref}\" | .${key}.skip = ((.${key}.skip // []) - [\"${ref}\"])${partner_reset}" "$commit_msg"
    mirror_promote "$key" "$ref" "$MIRROR_LABEL"
    close_proposals "$key" "Closed: a newer build passed, pin moved to \`${ref:0:7}\`."
    for partner_key in "${COMPONENTS[@]}"; do
        [ "$partner_key" = "$key" ] && continue
        close_proposals "$partner_key" "Closed: $(component_label "$key") moved to pin \`${ref:0:7}\`, skip list reset."
    done
}

handle_failed_candidate() {
    local key="$1" ref="$2" tail="not in run_variant/run_build (kernel ${KERNEL_VERSION})"

    case "$(failure_stage)" in
        setup)
            log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed before run_variant (setup/restore-source/branding), ${tail}"
            ;;
        core_addons)
            log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed in an unrelated stage (run_core/run_addons), ${tail}"
            ;;
        release)
            log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed in an unrelated stage (run_release), ${tail}"
            ;;
        candidate)
            warn "checkpoint: ${key} candidate ${ref:0:12} failed on kernel ${KERNEL_VERSION} — not skipped yet, opening proposal for approval"
            propose_skip "$key" "$ref"
            ;;
    esac
}

main() {
    local key ref

    sync_mirrors
    init_remote
    prune_proposal_branches

    if ! any_candidate_used; then
        log "checkpoint: no candidate ref used this run — nothing to update"
        return 0
    fi

    case "$BUILD_OUTCOME" in
        success|failure) ;;
        *)
            log "checkpoint: build ended '${BUILD_OUTCOME}' (cancelled, timed out or skipped) — candidates left untouched"
            return 0
            ;;
    esac

    for key in "${COMPONENTS[@]}"; do
        is_candidate "$key" || continue
        ref="$(candidate_ref "$key")"
        if [ "$BUILD_OUTCOME" = "success" ]; then
            promote_candidate "$key" "$ref"
        else
            handle_failed_candidate "$key" "$ref"
        fi
    done
}

main
