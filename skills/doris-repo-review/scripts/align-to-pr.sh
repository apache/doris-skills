#!/usr/bin/env bash
# Align the CURRENT worktree to the exact head commit of a GitHub PR.
#
# Usage:
#   align-to-pr.sh <PR-URL | owner/repo#N | N> [--repo <owner/repo>] [--check] [--out <file>]
#
#   --repo <owner/repo>  upstream repo when the argument is a bare number (default apache/doris)
#   --check              report the diagnosis and change nothing
#   --out <file>         write align.env here (default: stdout only)
#
# Scope: the worktree the command runs in. No other directory is looked at, no
# worktree is created, no environment variable selects a different checkout.
#
# Safety: the switch is refused outright when the worktree has modified tracked
# files or an operation in progress - the user commits or stashes, never this
# script. The switch itself is `git checkout --detach`, so no branch ref moves
# and nothing is reset or deleted. Untracked files are left alone: git never
# deletes them on checkout and refuses when it would overwrite one.
set -euo pipefail

PR_ARG=""
UPSTREAM_REPO=""
OUT_FILE=""
CHECK_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)    UPSTREAM_REPO="$2"; shift 2 ;;
        --check)   CHECK_ONLY=1; shift ;;
        --out)     OUT_FILE="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        -*)        echo "unknown option: $1" >&2; exit 2 ;;
        *)         PR_ARG="$1"; shift ;;
    esac
done

[ -n "$PR_ARG" ] || { echo "ERROR: no PR given. Pass a PR URL, owner/repo#N, or a number." >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI is required." >&2; exit 1; }

# ---------------------------------------------------------------- parse the PR ref
PR_NUMBER=""
if [[ "$PR_ARG" =~ ^(https?://)?(www\.)?github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    UPSTREAM_REPO="${BASH_REMATCH[3]}/${BASH_REMATCH[4]}"
    PR_NUMBER="${BASH_REMATCH[5]}"
elif [[ "$PR_ARG" =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]; then
    UPSTREAM_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    PR_NUMBER="${BASH_REMATCH[3]}"
elif [[ "$PR_ARG" =~ ^#?([0-9]+)$ ]]; then
    PR_NUMBER="${BASH_REMATCH[1]}"
else
    echo "ERROR: cannot parse '$PR_ARG' as a PR reference." >&2
    exit 2
fi
[ -n "$UPSTREAM_REPO" ] || UPSTREAM_REPO="apache/doris"

WORKDIR="$(git rev-parse --show-toplevel)"

# ------------------------------------------------------------------ PR metadata
read_pr() {
    gh api "repos/${UPSTREAM_REPO}/pulls/${PR_NUMBER}" \
        --jq '[.title, .state, .head.ref, (.head.repo.full_name // "DELETED"), .head.sha, .base.ref, .base.sha] | @tsv'
}
if ! PR_TSV="$(read_pr 2>/dev/null)"; then
    echo "ERROR: cannot read ${UPSTREAM_REPO}#${PR_NUMBER} (wrong repo/number, or gh is not authenticated)." >&2
    exit 1
fi
IFS=$'\t' read -r PR_TITLE PR_STATE PR_HEAD_REF PR_HEAD_REPO PR_HEAD_SHA PR_BASE_REF PR_BASE_SHA <<<"$PR_TSV"

# ------------------------------------------------------------------ local state
HEAD_SHA="$(git rev-parse HEAD)"
CURRENT_REF="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short=12 HEAD)"
DIRTY="$(git status --porcelain --untracked-files=no | grep -c . || true)"
UNTRACKED="$(git ls-files --others --exclude-standard | grep -c . || true)"

IN_PROGRESS=""
for d in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    if [ -e "$(git rev-parse --path-format=absolute --git-path "$d")" ]; then IN_PROGRESS="$d"; break; fi
done

# ------------------------------------------------------------ fetch the PR head
# refs/pull/N/head works for fork PRs too, so no fork remote has to be added.
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
find_remote() {
    local want slug url name
    want="$(lower "$1")"
    for name in $(git remote); do
        url="$(git remote get-url "$name" 2>/dev/null || true)"
        slug="$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/$##')"
        if [ "$(lower "$slug")" = "$want" ]; then printf '%s' "$name"; return 0; fi
    done
    return 1
}
if REMOTE="$(find_remote "$UPSTREAM_REPO")"; then
    FETCH_FROM="$REMOTE"; FETCH_VIA="remote '$REMOTE'"
else
    FETCH_FROM="https://github.com/${UPSTREAM_REPO}.git"
    FETCH_VIA="URL (no local remote points at ${UPSTREAM_REPO})"
fi

PR_REF="refs/doris-review/pr-${PR_NUMBER}"
if [ "$CHECK_ONLY" = "0" ]; then
    git fetch --no-tags --quiet "$FETCH_FROM" "+refs/pull/${PR_NUMBER}/head:${PR_REF}"

    FETCHED_SHA="$(git rev-parse "$PR_REF")"
    if [ "$FETCHED_SHA" != "$PR_HEAD_SHA" ]; then
        # Mirrors the CI guard: the PR moved between the API read and the fetch.
        IFS=$'\t' read -r PR_TITLE PR_STATE PR_HEAD_REF PR_HEAD_REPO PR_HEAD_SHA PR_BASE_REF PR_BASE_SHA <<<"$(read_pr)"
        if [ "$FETCHED_SHA" != "$PR_HEAD_SHA" ]; then
            echo "ERROR: the PR head moved while preparing (api=$PR_HEAD_SHA fetched=$FETCHED_SHA)." >&2
            echo "       re-run the command." >&2
            exit 1
        fi
    fi

    if ! git cat-file -e "${PR_BASE_SHA}^{commit}" 2>/dev/null; then
        git fetch --no-tags --quiet "$FETCH_FROM" \
            "+refs/heads/${PR_BASE_REF}:refs/doris-review/base-${PR_NUMBER}" || true
    fi
fi
BASE_PRESENT=1
git cat-file -e "${PR_BASE_SHA}^{commit}" 2>/dev/null || BASE_PRESENT=0

# ------------------------------------- how this worktree relates to the PR head
BRANCH_MATCHES_PR=0
[ "$CURRENT_REF" = "$PR_HEAD_REF" ] && BRANCH_MATCHES_PR=1

LOCAL_VS_PR="unknown"
if git cat-file -e "${PR_HEAD_SHA}^{commit}" 2>/dev/null; then
    if [ "$HEAD_SHA" = "$PR_HEAD_SHA" ]; then
        LOCAL_VS_PR="same"
    elif git merge-base --is-ancestor "$PR_HEAD_SHA" "$HEAD_SHA" 2>/dev/null; then
        LOCAL_VS_PR="ahead:$(git rev-list --count "${PR_HEAD_SHA}..${HEAD_SHA}")"
    elif git merge-base --is-ancestor "$HEAD_SHA" "$PR_HEAD_SHA" 2>/dev/null; then
        LOCAL_VS_PR="behind:$(git rev-list --count "${HEAD_SHA}..${PR_HEAD_SHA}")"
    elif git merge-base "$HEAD_SHA" "$PR_HEAD_SHA" >/dev/null 2>&1; then
        LOCAL_VS_PR="diverged:$(git rev-list --left-right --count "${PR_HEAD_SHA}...${HEAD_SHA}" | tr '\t' '/')"
    else
        LOCAL_VS_PR="unrelated"
    fi
fi

# ------------------------------------------------------------------ the decision
PREV_REF=""
PREV_SHA=""
BLOCKED_REASON=""
if [ "$HEAD_SHA" = "$PR_HEAD_SHA" ]; then
    ALIGN_MODE="already"
elif [ -n "$IN_PROGRESS" ]; then
    ALIGN_MODE="blocked"
    BLOCKED_REASON="'$IN_PROGRESS' is in progress; finish or abort it, then re-run"
elif [ "$DIRTY" -gt 0 ]; then
    ALIGN_MODE="blocked"
    BLOCKED_REASON="$DIRTY modified tracked file(s) would be carried onto the PR commit and pollute the review; commit or stash them yourself, then re-run"
else
    ALIGN_MODE="switched"
    PREV_REF="$CURRENT_REF"
    PREV_SHA="$HEAD_SHA"
    if [ "$CHECK_ONLY" = "0" ]; then
        git checkout --detach --quiet "$PR_REF"
        ACTUAL_SHA="$(git rev-parse HEAD)"
        if [ "$ACTUAL_SHA" != "$PR_HEAD_SHA" ]; then
            echo "ERROR: worktree is at $ACTUAL_SHA, expected the PR head $PR_HEAD_SHA." >&2
            exit 1
        fi
    fi
fi

# Refuse for real only when actually asked to act; --check still prints the diagnosis.
if [ "$ALIGN_MODE" = "blocked" ] && [ "$CHECK_ONLY" = "0" ]; then
    echo "ERROR: cannot switch $WORKDIR to the PR head." >&2
    echo "       $BLOCKED_REASON." >&2
    git status --porcelain --untracked-files=no | sed 's/^/         /' >&2
    echo "       This script never commits, stashes, resets or deletes anything for you." >&2
    exit 1
fi

emit() {
    cat <<EOF
UPSTREAM_REPO=$UPSTREAM_REPO
PR_NUMBER=$PR_NUMBER
PR_URL=https://github.com/${UPSTREAM_REPO}/pull/${PR_NUMBER}
PR_TITLE=$PR_TITLE
PR_STATE=$PR_STATE
PR_HEAD_REF=$PR_HEAD_REF
PR_HEAD_REPO=$PR_HEAD_REPO
PR_HEAD_SHA=$PR_HEAD_SHA
PR_BASE_REF=$PR_BASE_REF
PR_BASE_SHA=$PR_BASE_SHA
BASE_PRESENT=$BASE_PRESENT
PR_LOCAL_REF=$PR_REF
ALIGN_MODE=$ALIGN_MODE
WORKDIR=$WORKDIR
DOCS_ROOT=$WORKDIR
PREV_REF=$PREV_REF
PREV_SHA=$PREV_SHA
BEFORE_REF=$CURRENT_REF
BEFORE_HEAD_SHA=$HEAD_SHA
DIRTY=$DIRTY
UNTRACKED=$UNTRACKED
BRANCH_MATCHES_PR=$BRANCH_MATCHES_PR
LOCAL_VS_PR=$LOCAL_VS_PR
EOF
}

if [ -n "$OUT_FILE" ] && [ "$CHECK_ONLY" = "0" ]; then
    mkdir -p "$(dirname "$OUT_FILE")"
    emit > "$OUT_FILE"
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo "=== plan for ${UPSTREAM_REPO}#${PR_NUMBER} (check only, nothing was changed) ==="
else
    echo "=== aligned to ${UPSTREAM_REPO}#${PR_NUMBER} ==="
fi
emit
echo
echo "worktree      : $WORKDIR"
if [ "$BRANCH_MATCHES_PR" = "1" ]; then
    echo "branch check  : '$CURRENT_REF' IS the PR head branch"
else
    echo "branch check  : '$CURRENT_REF' is NOT the PR head branch ('$PR_HEAD_REF' of $PR_HEAD_REPO)"
fi
case "$LOCAL_VS_PR" in
    same)       echo "commit check  : HEAD equals the PR head" ;;
    ahead:*)    echo "commit check  : HEAD is ${LOCAL_VS_PR#ahead:} commit(s) AHEAD of the PR head (that work is NOT reviewed)" ;;
    behind:*)   echo "commit check  : HEAD is ${LOCAL_VS_PR#behind:} commit(s) BEHIND the PR head" ;;
    diverged:*) echo "commit check  : HEAD has DIVERGED from the PR head (pr/local = ${LOCAL_VS_PR#diverged:})" ;;
    unrelated)  echo "commit check  : HEAD shares no history with the PR head" ;;
    unknown)    echo "commit check  : PR head not present locally yet (fetched when not running --check)" ;;
esac
echo "fetch source  : $FETCH_VIA"
WOULD=""; [ "$CHECK_ONLY" = "1" ] && WOULD="would "
case "$ALIGN_MODE" in
    already) echo "action        : none - this worktree is already at the PR head" ;;
    blocked) echo "action        : BLOCKED - $BLOCKED_REASON" ;;
    *)       echo "action        : ${WOULD}detach this worktree from '$CURRENT_REF' to the PR head" ;;
esac
[ "$UNTRACKED" -eq 0 ] || echo "note          : $UNTRACKED untracked file(s) are left in place (checkout never removes them)"
[ "$BASE_PRESENT" = "1" ] || echo "WARNING       : PR base commit $PR_BASE_SHA is not available locally; the diff will fall back to a local base ref."
echo
echo "review docs   : ${WORKDIR}/review-docs/"
[ -z "$PREV_REF" ] || echo "to restore    : git -C $WORKDIR checkout $PREV_REF"
[ "$ALIGN_MODE" != "blocked" ] || exit 1
