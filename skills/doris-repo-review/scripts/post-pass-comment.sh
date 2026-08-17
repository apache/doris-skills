#!/usr/bin/env bash
# Render and post the machine-readable PASS comment of a doris-repo-review run.
#
# Usage:
#   post-pass-comment.sh --ctx <dir> --model <id> [options]
#
#   --ctx <dir>            review context directory (must contain meta.env)
#   --model <id>           exact model id of the reviewing agent, e.g. claude-opus-5[1m]
#   --effort <s>           reasoning effort (default: $CLAUDE_EFFORT, else "unknown")
#   --findings b,m,mi,n    blocker,major,minor,nit counts (default 0,0,0,0)
#   --rounds <n>           convergence rounds actually run (default 1)
#   --converged true|false (default true)
#   --notes-file <f>       markdown bullet list for "Notes for maintainers"
#   --dry-run              run every precondition, render the body, post nothing
#   --force-new            always create a new comment, never update in place
#   --allow-closed         allow posting on a non-open PR
#
# Only a PASS is ever posted: blocker and major counts must both be 0, which is
# the same verdict rule the review documents use. The body layout is fixed here
# on purpose - the agent supplies the notes, never the format.
#
# Rendered body: <ctx>/pr-comment.md   Posted URL: <ctx>/pr-comment.url
set -euo pipefail

CTX=""
MODEL=""
EFFORT="${CLAUDE_EFFORT:-unknown}"
FINDINGS="0,0,0,0"
ROUNDS="1"
CONVERGED="true"
NOTES_FILE=""
DRY_RUN=0
FORCE_NEW=0
ALLOW_CLOSED=0

while [ $# -gt 0 ]; do
    case "$1" in
        --ctx)          CTX="$2"; shift 2 ;;
        --model)        MODEL="$2"; shift 2 ;;
        --effort)       EFFORT="$2"; shift 2 ;;
        --findings)     FINDINGS="$2"; shift 2 ;;
        --rounds)       ROUNDS="$2"; shift 2 ;;
        --converged)    CONVERGED="$2"; shift 2 ;;
        --notes-file)   NOTES_FILE="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=1; shift ;;
        --force-new)    FORCE_NEW=1; shift ;;
        --allow-closed) ALLOW_CLOSED=1; shift ;;
        -h|--help)      sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

BEGIN_MARKER='<!-- doris-repo-review:v1:begin -->'
END_MARKER='<!-- doris-repo-review:v1:end -->'
SCHEMA='doris-repo-review/v1'

# ------------------------------------------------------------------ preconditions
[ -n "$CTX" ] || { echo "ERROR: --ctx is required." >&2; exit 2; }
META="$CTX/meta.env"
[ -f "$META" ] || { echo "ERROR: $META not found - run prepare-review-context.sh first." >&2; exit 2; }
[ -n "$MODEL" ] || { echo "ERROR: --model is required; state the exact model id, never a guess." >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI is required." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required." >&2; exit 1; }

read_meta() { sed -n "s/^$1=//p" "$META" | head -n 1; }
UPSTREAM_REPO="$(read_meta UPSTREAM_REPO)"
PR_NUMBER="$(read_meta PR_NUMBER)"
PR_URL="$(read_meta PR_URL)"
BASE_SHA="$(read_meta BASE_SHA)"
HEAD_SHA="$(read_meta HEAD_SHA)"
REPO_ROOT="$(read_meta REPO_ROOT)"

[ -n "$PR_NUMBER" ] || { echo "ERROR: meta.env has no PR_NUMBER - this review is not attached to a PR." >&2; exit 2; }
[ -n "$UPSTREAM_REPO" ] || { echo "ERROR: meta.env has no UPSTREAM_REPO." >&2; exit 2; }
[ -n "$PR_URL" ] || PR_URL="https://github.com/${UPSTREAM_REPO}/pull/${PR_NUMBER}"

case "$CONVERGED" in true|false) ;; *) echo "ERROR: --converged takes true or false." >&2; exit 2 ;; esac
[[ "$ROUNDS" =~ ^[0-9]+$ ]] || { echo "ERROR: --rounds takes a number." >&2; exit 2; }
IFS=',' read -r F_BLOCKER F_MAJOR F_MINOR F_NIT <<<"$FINDINGS"
for v in "$F_BLOCKER" "$F_MAJOR" "$F_MINOR" "$F_NIT"; do
    [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERROR: --findings takes blocker,major,minor,nit as four numbers." >&2; exit 2; }
done

# The verdict rule: any Blocker or Major means REQUEST_CHANGES, and a
# REQUEST_CHANGES review posts nothing at all.
if [ "$F_BLOCKER" -gt 0 ] || [ "$F_MAJOR" -gt 0 ]; then
    echo "ERROR: $F_BLOCKER blocker(s) and $F_MAJOR major(s) mean REQUEST_CHANGES." >&2
    echo "       This skill posts a comment only when the review passes. Nothing was posted." >&2
    exit 1
fi

# ------------------------------------------------------------------------- notes
NOTES_BODY="_None._"
NOTE_COUNT=0
if [ -n "$NOTES_FILE" ]; then
    [ -f "$NOTES_FILE" ] || { echo "ERROR: --notes-file not found: $NOTES_FILE" >&2; exit 2; }
    if grep -q . "$NOTES_FILE"; then
        if grep -q 'doris-repo-review:v1' "$NOTES_FILE"; then
            echo "ERROR: the notes file contains a v1 marker; that would break comment detection." >&2
            exit 2
        fi
        while IFS= read -r line; do
            [ -n "${line//[[:space:]]/}" ] || continue
            case "$line" in
                "- "*) NOTE_COUNT=$((NOTE_COUNT + 1)) ;;
                "  "*) : ;;   # continuation of the previous bullet
                *) echo "ERROR: every note line must be a '- ' bullet or a 2-space continuation: $line" >&2; exit 2 ;;
            esac
        done < "$NOTES_FILE"
        [ "$NOTE_COUNT" -le 5 ] || { echo "ERROR: at most 5 notes; got $NOTE_COUNT. Keep the rest in the review document." >&2; exit 2; }
        NOTES_BODY="$(cat "$NOTES_FILE")"
    fi
fi
if [ "$CONVERGED" = "false" ] && [ "$NOTE_COUNT" -eq 0 ]; then
    echo "ERROR: converged=false needs at least one note saying what was left open." >&2
    exit 2
fi

# ------------------------------------------------------------------ live PR state
PR_TSV="$(gh api "repos/${UPSTREAM_REPO}/pulls/${PR_NUMBER}" --jq '[.head.sha, .state] | @tsv')" || {
    echo "ERROR: cannot read ${UPSTREAM_REPO}#${PR_NUMBER}." >&2; exit 1; }
IFS=$'\t' read -r LIVE_HEAD_SHA LIVE_STATE <<<"$PR_TSV"

if [ "$LIVE_HEAD_SHA" != "$HEAD_SHA" ]; then
    echo "ERROR: the PR head moved since the review." >&2
    echo "       reviewed : $HEAD_SHA" >&2
    echo "       PR now at: $LIVE_HEAD_SHA" >&2
    echo "       Posting would sign off a commit that was never reviewed. Re-run the review." >&2
    exit 1
fi
if [ "$LIVE_STATE" != "open" ] && [ "$ALLOW_CLOSED" = "0" ]; then
    echo "ERROR: ${UPSTREAM_REPO}#${PR_NUMBER} is '$LIVE_STATE', not open. Pass --allow-closed to post anyway." >&2
    exit 1
fi

if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/.git" ]; then
    LOCAL_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$LOCAL_HEAD" ] && [ "$LOCAL_HEAD" != "$HEAD_SHA" ]; then
        echo "NOTE: $REPO_ROOT is no longer parked on the reviewed commit (now $LOCAL_HEAD)." >&2
        echo "      That is fine if you switched back after the review; the comment still refers to $HEAD_SHA." >&2
    fi
fi

# Three ways to name the posting account: the REST /user endpoint has been seen answering 503
# while the rest of the API is healthy, and on an error gh still prints the error JSON on stdout,
# so each candidate is validated as a real login before it is accepted.
try_login() {
    local out
    out="$("$@" 2>/dev/null || true)"
    out="$(printf '%s' "$out" | tr -d '[:space:]')"
    [[ "$out" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ ]] || return 1
    printf '%s' "$out"
}
auth_status_login() {
    gh auth status 2>&1 | sed -n 's/.*Logged in to github.com account \([^ ]*\).*/\1/p' | head -n 1
}
REVIEWER="$(try_login gh api user --jq .login || true)"
[ -n "$REVIEWER" ] || REVIEWER="$(try_login gh api graphql -f "query={viewer{login}}" --jq .data.viewer.login || true)"
[ -n "$REVIEWER" ] || REVIEWER="$(try_login auth_status_login || true)"
[ -n "$REVIEWER" ] || { echo "ERROR: cannot determine which GitHub account gh is logged in as." >&2; exit 1; }
REVIEWED_AT="$(python3 -c "import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec='minutes'))")"

# ------------------------------------------------------------------ render body
FENCE='```'
DISCLAIMER='<sub>Reviewed locally with the `doris-repo-review` pipeline (a local port of `.github/workflows/code-review-runner.yml`). This is not a CI status check.</sub>'
BODY_FILE="$CTX/pr-comment.md"
cat > "$BODY_FILE" <<EOF
${BEGIN_MARKER}
### Local pipeline review — ✅ PASS

${FENCE}yaml
schema: ${SCHEMA}
status: PASS
pr: ${UPSTREAM_REPO}#${PR_NUMBER}
commit: ${HEAD_SHA}
base: ${BASE_SHA}
reviewed_at: ${REVIEWED_AT}
reviewer: ${REVIEWER}
model: ${MODEL}
effort: ${EFFORT}
findings: {blocker: ${F_BLOCKER}, major: ${F_MAJOR}, minor: ${F_MINOR}, nit: ${F_NIT}}
rounds: ${ROUNDS}
converged: ${CONVERGED}
${FENCE}

**Notes for maintainers**

${NOTES_BODY}

${DISCLAIMER}
${END_MARKER}
EOF

# ------------------------------------------- find an earlier comment of this tool
# Own comments only - another account's comment cannot be edited anyway. A comment for THIS
# commit wins wherever it sits in the thread; otherwise the newest one is kept just to report
# which commit the previous run signed off on.
SAME_ID=""
LAST_ID=""
LAST_COMMIT=""
while IFS=$'\t' read -r cid clogin ccommit; do
    [ -n "$cid" ] || continue
    [ "$clogin" = "$REVIEWER" ] || continue
    ccommit="${ccommit#commit: }"
    LAST_ID="$cid"
    LAST_COMMIT="$ccommit"
    [ "$ccommit" = "$HEAD_SHA" ] && SAME_ID="$cid"
done < <(gh api "repos/${UPSTREAM_REPO}/issues/${PR_NUMBER}/comments" --paginate \
            --jq '.[] | select(.body | test("doris-repo-review:v1:begin")) | [ .id, .user.login, ([.body | scan("commit: [0-9a-f]{40}")] | .[0] // "") ] | @tsv' 2>/dev/null || true)

ACTION="create"
EXISTING_ID=""
if [ -n "$SAME_ID" ] && [ "$FORCE_NEW" = "0" ]; then
    ACTION="update"
    EXISTING_ID="$SAME_ID"
fi

echo "=== doris-repo-review PASS comment ==="
echo "pr        : ${PR_URL}"
echo "commit    : ${HEAD_SHA}"
echo "reviewer  : ${REVIEWER}"
echo "model     : ${MODEL} (effort ${EFFORT})"
echo "findings  : blocker=${F_BLOCKER} major=${F_MAJOR} minor=${F_MINOR} nit=${F_NIT}"
echo "notes     : ${NOTE_COUNT}"
if [ "$ACTION" = "update" ]; then
    echo "action    : UPDATE the existing comment ${EXISTING_ID} (same commit)"
elif [ -n "$LAST_ID" ]; then
    echo "action    : CREATE a new comment (the previous one, ${LAST_ID}, was for ${LAST_COMMIT:-an unknown commit})"
else
    echo "action    : CREATE a new comment"
fi
echo "body file : ${BODY_FILE}"
echo "--------------------------------------------------------------------------"
cat "$BODY_FILE"
echo "--------------------------------------------------------------------------"

if [ "$DRY_RUN" = "1" ]; then
    echo "dry run - nothing was posted."
    exit 0
fi

if [ "$ACTION" = "update" ]; then
    RESP="$(jq -n --rawfile body "$BODY_FILE" '{body: $body}' \
        | gh api --method PATCH "repos/${UPSTREAM_REPO}/issues/comments/${EXISTING_ID}" --input -)"
else
    RESP="$(jq -n --rawfile body "$BODY_FILE" '{body: $body}' \
        | gh api --method POST "repos/${UPSTREAM_REPO}/issues/${PR_NUMBER}/comments" --input -)"
fi
COMMENT_URL="$(printf '%s' "$RESP" | jq -r '.html_url')"
printf '%s\n' "$COMMENT_URL" > "$CTX/pr-comment.url"
echo "posted    : ${COMMENT_URL}"
