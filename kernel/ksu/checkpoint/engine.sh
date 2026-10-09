#!/usr/bin/env bash

# ======================================================
# 🚦 CHECKPOINT — Engine
# ======================================================
# Syncs pinned refs to their mirrors, promotes verified candidates, and files known-bad proposals for approval

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

apply_and_push() {
    local jq_patch="$1" commit_msg="$2"
    local attempt=1 max_attempts=5

    [ -n "${PERSONAL_TOKEN:-}" ] || error "checkpoint: PERSONAL_TOKEN not set — cannot push manifest update"

    git config --global user.name  "luminaire-bot"
    git config --global user.email "luminaire-bot@users.noreply.github.com"

    REMOTE="https://x-access-token:${PERSONAL_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

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

file_issue() {
    local key="$1" ref="$2" others="$3"
    local title="🔴 Upstream build failure: ${key} (${KERNEL_VERSION})"
    local run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    local stage existing body

    if [ "${CHECKPOINT_VARIANT_OK:-false}" = "true" ]; then
        stage="run_build (compile)"
    else
        stage="run_variant (root solution / SuSFS)"
    fi

    existing=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"${title}\"" --json number --jq '.[0].number' 2>/dev/null || true)

    body="<!-- luminaire-bad key=${key} ref=${ref} kernel=${KERNEL_VERSION} -->
Candidate \`${ref}\` for **${key}** failed during ${stage} on kernel ${KERNEL_VERSION} (run: ${run_url}).

It is **not** marked known-bad — the manifest is untouched and the pin stays on the last known-good commit. Trace the failure upstream first. If the break is real and cannot be fixed on our side, add the \`approve-bad\` label to this issue to blacklist this exact commit. If it looks like a false positive, leave it or close the issue.

This issue will auto-close once a build succeeds again for ${key}."

    if [ -n "$others" ]; then
        body="${body}

Other candidates in the same run (blame is not isolated, any of them may be the cause):
${others}"
    fi

    if [ -n "$existing" ] && [ "$existing" != "null" ]; then
        gh issue edit "$existing" --repo "$GITHUB_REPOSITORY" --body "$body" || warn "file_issue: couldn't update existing issue #${existing}"
        gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "Candidate \`${ref}\` failed again (run: ${run_url}). Issue body now points at this commit." || warn "file_issue: couldn't comment on existing issue #${existing}"
    else
        gh label create "upstream-broken" --repo "$GITHUB_REPOSITORY" \
            --color "d73a4a" --description "Auto-filed: an upstream pin candidate failed to build" \
            2>/dev/null || true
        gh label create "approve-bad" --repo "$GITHUB_REPOSITORY" \
            --color "b60205" --description "Approve blacklisting the candidate proposed in this issue" \
            2>/dev/null || true
        gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --body "$body" --label "upstream-broken" || warn "file_issue: couldn't create issue for ${key}"
    fi
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

    file_issue "$key" "$ref" "$others"
}

close_issue_if_open() {
    local key="$1"
    local title="🔴 Upstream build failure: ${key} (${KERNEL_VERSION})"
    local existing
    existing=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "in:title \"${title}\"" --json number --jq '.[0].number' 2>/dev/null || true)
    [ -n "$existing" ] && [ "$existing" != "null" ] && \
        gh issue close "$existing" --repo "$GITHUB_REPOSITORY" --comment "✅ Build succeeded again — pin promoted to a new known-good commit." 2>/dev/null || true
}

if [ "$BUILD_OUTCOME" = "approve-bad" ]; then
    approve_key="${COMPONENTS[0]:-}"
    approve_ref="${COMPONENTS[1]:-}"

    [[ "$approve_key" =~ ^[a-z0-9_]+$ ]] || error "checkpoint: invalid component key '${approve_key}'"
    [[ "$approve_ref" =~ ^[0-9a-f]{40}$ ]] || error "checkpoint: invalid ref '${approve_ref}'"
    jq -e --arg k "$approve_key" 'has($k)' "$MANIFEST" > /dev/null 2>&1 \
        || error "checkpoint: component '${approve_key}' not found in ${MANIFEST_REL}"
    [ "$(jq -r --arg k "$approve_key" '.[$k].good // ""' "$MANIFEST")" != "$approve_ref" ] \
        || error "checkpoint: ${approve_ref:0:12} is the current known-good pin for ${approve_key} — refusing to blacklist it"

    warn "checkpoint: approved — blacklisting ${approve_key} candidate ${approve_ref:0:12} (kernel ${KERNEL_VERSION})"
    apply_and_push ".${approve_key}.bad |= (. + [\"${approve_ref}\"] | unique)" "chore: mark ${approve_key} candidate ${approve_ref:0:12} as known-bad for kernel ${KERNEL_VERSION} (run ${GITHUB_RUN_ID})"
    exit 0
fi

for key in "${COMPONENTS[@]}"; do
    pinned_ref="$(jq -r ".${key}.good // \"\"" "$MANIFEST" 2>/dev/null || true)"
    [ -n "$pinned_ref" ] || continue
    mirror_sync "$key" "$pinned_ref" "$MIRROR_LABEL"
done

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
        apply_and_push ".${key}.good = \"${ref}\" | .${key}.bad = ((.${key}.bad // []) - [\"${ref}\"])" "chore: bump ${key} pin to ${ref:0:12} for kernel ${KERNEL_VERSION} (verified via run ${GITHUB_RUN_ID})"
        mirror_promote "$key" "$ref" "$MIRROR_LABEL"
        close_issue_if_open "$key"
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

    warn "checkpoint: ${key} candidate ${ref:0:12} failed on kernel ${KERNEL_VERSION} — not blacklisted, filing issue for approval"
    propose_bad "$key" "$ref"
done
