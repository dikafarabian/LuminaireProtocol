#!/usr/bin/env bash

# ======================================================
# 🚦 CHECKPOINT — Engine
# ======================================================
# Syncs pinned refs to their mirrors, promotes verified candidates, opens known-bad proposals as pull requests, and prunes finished proposal branches

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

proposal_prefix() {
    echo "bad-pin/${1}-${KERNEL_VERSION}-"
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
    done <<< "$(git ls-remote --heads "$REMOTE" 'refs/heads/bad-pin/*' | awk '{sub("refs/heads/", "", $2); print $2}')"
}

file_proposal() {
    local key="$1" ref="$2" others="$3"
    local branch="$(proposal_prefix "$key")${ref:0:12}"
    local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    local stage existing body tree

    if [ "${CHECKPOINT_VARIANT_OK:-false}" = "true" ]; then
        stage="run_build (compile)"
    else
        stage="run_variant (root solution / SuSFS)"
    fi

    existing="$(open_proposals "$key")"
    if [[ $'\n'"${existing}"$'\n' == *" ${branch}"$'\n'* ]]; then
        log "checkpoint: proposal for ${key} ${ref:0:12} is already open"
        return 0
    fi
    close_proposals "$key" "Superseded by a newer failing candidate (\`${ref:0:12}\`)." "$branch"

    init_remote
    run_quiet git fetch "$REMOTE" main
    tree="$(mktemp -d)"
    git worktree add -q --detach "$tree" FETCH_HEAD
    if ! (
        cd "$tree" \
        && git checkout -q -b "$branch" \
        && jq --arg ref "$ref" ".${key}.bad |= (. + [\$ref] | unique)" "$MANIFEST_REL" > "${MANIFEST_REL}.tmp" \
        && mv "${MANIFEST_REL}.tmp" "$MANIFEST_REL" \
        && git add "$MANIFEST_REL" \
        && git commit -q -m "chore: mark ${key} candidate ${ref:0:12} as known-bad for kernel ${KERNEL_VERSION} (run ${GITHUB_RUN_ID})" \
        && git push -q --force "$REMOTE" "$branch"
    ); then
        warn "checkpoint: couldn't push proposal branch for ${key}"
        git worktree remove --force "$tree"
        return 0
    fi
    git worktree remove --force "$tree"

    body="Candidate \`${ref}\` for **${key}** failed during ${stage} on kernel ${KERNEL_VERSION} ([run](${run_url})).

Merge to mark this exact commit known-bad. Close to ignore it. The pin stays on the last known-good commit either way, and this proposal closes itself once a build succeeds again for ${key}."

    if [ -n "$others" ]; then
        body="${body}

Other candidates in the same run (blame is not isolated, any of them may be the cause):
${others}"
    fi

    gh pr create --repo "$GITHUB_REPOSITORY" --base main --head "$branch" \
        --title "🚫 Mark bad: ${key} ${ref:0:12} (${KERNEL_VERSION})" --body "$body" \
        || warn "checkpoint: couldn't open proposal for ${key}"
}

propose_bad() {
    local key="$1" ref="$2"
    local other_key other_prefix other_candidate other_ref_var others=""

    for other_key in "${COMPONENTS[@]}"; do
        [ "$other_key" = "$key" ] && continue
        other_prefix="${other_key^^}"
        other_candidate="CANDIDATE_${other_prefix}"
        [ "${!other_candidate:-false}" = "true" ] || continue
        other_ref_var="${other_prefix}_REF"
        others="${others}- \`${other_key}\` @ \`${!other_ref_var}\`
"
    done

    file_proposal "$key" "$ref" "$others"
}

for key in "${COMPONENTS[@]}"; do
    pinned_ref="$(jq -r ".${key}.good // \"\"" "$MANIFEST" 2>/dev/null || true)"
    [ -n "$pinned_ref" ] || continue
    mirror_sync "$key" "$pinned_ref" "$MIRROR_LABEL"
done

init_remote
prune_proposal_branches

any_candidate_used="false"
for key in "${COMPONENTS[@]}"; do
    prefix="${key^^}"
    candidate_var="CANDIDATE_${prefix}"
    [ "${!candidate_var:-false}" = "true" ] && any_candidate_used="true"
done

if [ "$any_candidate_used" = "false" ]; then
    log "checkpoint: no candidate ref used this run — nothing to update"
    exit 0
fi

case "$BUILD_OUTCOME" in
    success|failure) ;;
    *)
        log "checkpoint: build ended '${BUILD_OUTCOME}' (cancelled, timed out or skipped) — candidates left untouched"
        exit 0
        ;;
esac

for key in "${COMPONENTS[@]}"; do
    prefix="${key^^}"
    candidate_var="CANDIDATE_${prefix}"
    [ "${!candidate_var:-false}" = "true" ] || continue

    ref_var="${prefix}_REF"
    ref="${!ref_var}"

    if [ "$BUILD_OUTCOME" = "success" ]; then
        log "checkpoint: promoting ${key} pin to ${ref:0:12} (kernel ${KERNEL_VERSION})"
        partner_reset=""
        for partner_key in "${COMPONENTS[@]}"; do
            [ "$partner_key" = "$key" ] && continue
            partner_reset="${partner_reset} | if .${partner_key} then .${partner_key}.bad = [] else . end"
        done
        apply_and_push ".${key}.good = \"${ref}\" | .${key}.bad = ((.${key}.bad // []) - [\"${ref}\"])${partner_reset}" "chore: bump ${key} pin to ${ref:0:12} for kernel ${KERNEL_VERSION} (verified via run ${GITHUB_RUN_ID})"
        mirror_promote "$key" "$ref" "$MIRROR_LABEL"
        close_proposals "$key" "Build succeeded again — pin promoted to a new known-good commit."
        for partner_key in "${COMPONENTS[@]}"; do
            [ "$partner_key" = "$key" ] && continue
            close_proposals "$partner_key" "Partner ${key} was promoted to ${ref:0:12} — known-bad state reset, this proposal is stale."
        done
        continue
    fi

    if [ "${CHECKPOINT_PRE_VARIANT_OK:-false}" != "true" ]; then
        log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed before run_variant (setup/restore-source/branding), not in run_variant/run_build (kernel ${KERNEL_VERSION})"
        continue
    fi

    if [ "${CHECKPOINT_VARIANT_OK:-false}" = "true" ] && [ "${CHECKPOINT_ADDONS_OK:-false}" != "true" ]; then
        log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed in an unrelated stage (run_core/run_addons), not in run_variant/run_build (kernel ${KERNEL_VERSION})"
        continue
    fi

    if [ "${CHECKPOINT_ADDONS_OK:-false}" = "true" ] && [ "${CHECKPOINT_BUILD_OK:-false}" = "true" ]; then
        log "checkpoint: ${key} candidate ${ref:0:12} left untouched — build failed in an unrelated stage (run_release), not in run_variant/run_build (kernel ${KERNEL_VERSION})"
        continue
    fi

    warn "checkpoint: ${key} candidate ${ref:0:12} failed on kernel ${KERNEL_VERSION} — not blacklisted, opening proposal for approval"
    propose_bad "$key" "$ref"
done
