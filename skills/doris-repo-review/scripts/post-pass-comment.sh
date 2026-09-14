#!/usr/bin/env bash
# Render and post the machine-readable PASS comment of a doris-repo-review run.
#
# Usage:
#   post-pass-comment.sh --ctx <dir> [options]
#
#   --ctx <dir>            review context with meta.env, review-runtime.json, and EN/ZH docs
#   --notes-file <f>       markdown bullet list for "Notes for maintainers"
#   --dry-run              run every precondition, render the body, post nothing
#
# Runtime fields come from review-runtime.json. Review fields come directly from
# verify-review-docs.py. The agent supplies notes, never receipt fields or format.
# Refuses on anything that is not a converged APPROVE with zero Blocker/Major findings and
# zero regressions in a category that carries the Major floor; a regression in any other
# category (rated Minor/Nit) is allowed only when the notes disclose it.
#
# Rendered body: <ctx>/pr-comment.md   Posted URL: <ctx>/pr-comment.url
set -euo pipefail

CTX=""
NOTES_FILE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --ctx)          CTX="$2"; shift 2 ;;
        --notes-file)   NOTES_FILE="$2"; shift 2 ;;
        --dry-run)      DRY_RUN=1; shift ;;
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
RUNTIME_FILE="$CTX/review-runtime.json"
[ -f "$RUNTIME_FILE" ] || { echo "ERROR: $RUNTIME_FILE not found - record the qualified reviewer first." >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh CLI is required." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required." >&2; exit 1; }

read_meta() { sed -n "s/^$1=//p" "$META" | head -n 1; }
UPSTREAM_REPO="$(read_meta UPSTREAM_REPO)"
PR_NUMBER="$(read_meta PR_NUMBER)"
PR_URL="$(read_meta PR_URL)"
BASE_SHA="$(read_meta BASE_SHA)"
HEAD_SHA="$(read_meta HEAD_SHA)"
NORMALIZED_HEAD_SHA="$(printf '%s' "$HEAD_SHA" | tr '[:upper:]' '[:lower:]')"
REPO_ROOT="$(read_meta REPO_ROOT)"
DOCS_ROOT="$(read_meta DOCS_ROOT)"

[ -n "$PR_NUMBER" ] || { echo "ERROR: meta.env has no PR_NUMBER - this review is not attached to a PR." >&2; exit 2; }
[ -n "$UPSTREAM_REPO" ] || { echo "ERROR: meta.env has no UPSTREAM_REPO." >&2; exit 2; }
[ -n "$PR_URL" ] || PR_URL="https://github.com/${UPSTREAM_REPO}/pull/${PR_NUMBER}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="$(jq -er '.model | strings' "$RUNTIME_FILE")" || { echo "ERROR: invalid runtime model." >&2; exit 2; }
EFFORT="$(jq -er '.effort | strings' "$RUNTIME_FILE")" || { echo "ERROR: invalid runtime effort." >&2; exit 2; }
RUNTIME_COMMIT="$(jq -er '.commit | strings' "$RUNTIME_FILE")" || { echo "ERROR: invalid runtime commit." >&2; exit 2; }
"$SCRIPT_DIR/review-runtime-policy.sh" check "$MODEL" "$EFFORT" >/dev/null
[ "$RUNTIME_COMMIT" = "$NORMALIZED_HEAD_SHA" ] || {
    echo "ERROR: qualified reviewer runtime was recorded for $RUNTIME_COMMIT, not $NORMALIZED_HEAD_SHA." >&2
    exit 2
}

[ -n "$DOCS_ROOT" ] || DOCS_ROOT="$REPO_ROOT"
EN_DOC="$DOCS_ROOT/review-docs/pr-${PR_NUMBER}-review.en.md"
ZH_DOC="$DOCS_ROOT/review-docs/pr-${PR_NUMBER}-review.zh.md"
RESULT_JSON="$(python3 "$SCRIPT_DIR/verify-review-docs.py" --json --ctx "$CTX" \
    --doc "$EN_DOC" --doc "$ZH_DOC")" || {
    echo "ERROR: review documents failed verification. Nothing was posted." >&2
    exit 2
}
RESULT_COMMIT="$(jq -er '.commit | strings' <<<"$RESULT_JSON")"
VERDICT="$(jq -er '.verdict | strings' <<<"$RESULT_JSON")"
ROUNDS="$(jq -er '.rounds | numbers' <<<"$RESULT_JSON")"
CONVERGED="$(jq -r '.converged | if . == true then "true" else "false" end' <<<"$RESULT_JSON")"
F_BLOCKER="$(jq -er '.findings.blocker | numbers' <<<"$RESULT_JSON")"
F_MAJOR="$(jq -er '.findings.major | numbers' <<<"$RESULT_JSON")"
F_MINOR="$(jq -er '.findings.minor | numbers' <<<"$RESULT_JSON")"
F_NIT="$(jq -er '.findings.nit | numbers' <<<"$RESULT_JSON")"
F_REGRESSIONS="$(jq -er '.regressions | numbers' <<<"$RESULT_JSON")" || {
    echo "ERROR: the verifier did not report a regression count; update verify-review-docs.py." >&2
    exit 2
}
F_FLOORED_REGRESSIONS="$(jq -er '.floored_regressions | numbers' <<<"$RESULT_JSON")" || {
    echo "ERROR: the verifier did not report a floored-regression count; update verify-review-docs.py." >&2
    exit 2
}

[ "$RESULT_COMMIT" = "$NORMALIZED_HEAD_SHA" ] || { echo "ERROR: review documents target another commit." >&2; exit 2; }
[ "$VERDICT" = "APPROVE" ] || { echo "ERROR: review verdict is $VERDICT. Nothing was posted." >&2; exit 1; }
[ "$CONVERGED" = "true" ] || { echo "ERROR: review did not converge. Nothing was posted." >&2; exit 1; }
[ "$F_BLOCKER" -eq 0 ] && [ "$F_MAJOR" -eq 0 ] || {
    echo "ERROR: Blocker or Major findings cannot produce a PASS comment." >&2
    exit 1
}
# The verifier already floors a functional / data / resource / performance regression at Major,
# so this only fires when the two scripts disagree; a PASS receipt must never sit on top of an
# undeclared behaviour change in one of those categories.
[ "$F_FLOORED_REGRESSIONS" -eq 0 ] || {
    echo "ERROR: $F_FLOORED_REGRESSIONS finding(s) are regressions in a category that is at least Major; a PASS receipt cannot be issued. Nothing was posted." >&2
    exit 1
}

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
        while IFS= read -r line || [ -n "$line" ]; do
            [ -n "${line//[[:space:]]/}" ] || continue
            case "$line" in
                "- "*) NOTE_COUNT=$((NOTE_COUNT + 1)) ;;
                "  "*) [ "$NOTE_COUNT" -gt 0 ] || {
                    echo "ERROR: a note continuation must follow a '- ' bullet." >&2
                    exit 2
                } ;;
                *) echo "ERROR: every note line must be a '- ' bullet or a 2-space continuation: $line" >&2; exit 2 ;;
            esac
        done < "$NOTES_FILE"
        [ "$NOTE_COUNT" -le 5 ] || { echo "ERROR: at most 5 notes; got $NOTE_COUNT. Keep the rest in the review document." >&2; exit 2; }
        NOTES_BODY="$(cat "$NOTES_FILE")"
    fi
fi
# A regression outside the floored categories stays Minor/Nit, so the verdict is still APPROVE -
# but the receipt must not be silent about a behaviour change the PR body never declared.
if [ "$F_REGRESSIONS" -gt 0 ] && [ "$NOTE_COUNT" -eq 0 ]; then
    echo "ERROR: $F_REGRESSIONS finding(s) are undeclared behaviour changes (Regression: yes); the receipt must disclose each of them - list them as --notes-file bullets. Nothing was posted." >&2
    exit 1
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
if [ "$LIVE_STATE" != "open" ]; then
    echo "ERROR: ${UPSTREAM_REPO}#${PR_NUMBER} is '$LIVE_STATE', not open." >&2
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
DISCLAIMER='<sub>Reviewed locally with the `doris-repo-review` pipeline. Repository policy may accept this receipt for the matching commit; it is not a human Apache approval.</sub>'
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
COMMENTS_TSV="$(gh api "repos/${UPSTREAM_REPO}/issues/${PR_NUMBER}/comments" --paginate \
    --jq '.[] | select(.body | test("doris-repo-review:v1:begin")) | [ .id, .user.login, ([.body | scan("commit: [0-9a-f]{40}")] | .[0] // "") ] | @tsv')" || {
    echo "ERROR: cannot list existing review comments. Nothing was posted." >&2
    exit 1
}
while IFS=$'\t' read -r cid clogin ccommit; do
    [ -n "$cid" ] || continue
    [ "$clogin" = "$REVIEWER" ] || continue
    ccommit="${ccommit#commit: }"
    LAST_ID="$cid"
    LAST_COMMIT="$ccommit"
    [ "$ccommit" = "$HEAD_SHA" ] && SAME_ID="$cid"
done <<<"$COMMENTS_TSV"

ACTION="create"
EXISTING_ID=""
if [ -n "$SAME_ID" ]; then
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
[ "$F_REGRESSIONS" -eq 0 ] || echo "disclosed : ${F_REGRESSIONS} undeclared behaviour change(s) in non-blocking categories, named in the notes"
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
