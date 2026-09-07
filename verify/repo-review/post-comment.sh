#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/skills/doris-repo-review/scripts"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/doris-review-post.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
REPO="$TMP_ROOT/repo"
CTX="$TMP_ROOT/ctx"
HEAD_SHA="1111111111111111111111111111111111111111"
OTHER_SHA="3333333333333333333333333333333333333333"
BASE_SHA="2222222222222222222222222222222222222222"
PASS_COUNT=0
mkdir -p "$TMP_ROOT/bin" "$REPO/src" "$REPO/review-docs" "$CTX"
printf 'int answer = 42;\n' > "$REPO/src/Foo.java"
printf 'src/Foo.java\t1\t1\n' > "$CTX/changed_line_ranges.tsv"

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

expect_failure() {
    local label="$1" pattern="$2"
    shift 2
    if "$@" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
        fail "$label unexpectedly succeeded"
    fi
    if ! grep -Fq "$pattern" "$TMP_ROOT/err" && ! grep -Fq "$pattern" "$TMP_ROOT/out"; then
        fail "$label failed for the wrong reason"
    fi
    pass "$label"
}

write_meta() {
    cat > "$CTX/meta.env" <<EOF
UPSTREAM_REPO=apache/doris
PR_NUMBER=123
PR_URL=https://github.com/apache/doris/pull/123
BASE_SHA=$BASE_SHA
HEAD_SHA=$1
REPO_ROOT=$REPO
DOCS_ROOT=$REPO
EOF
}

write_docs() {
    local head="$1" verdict="$2" severity="$3" rounds="$4" convergence="$5"
    local zh_convergence=已收敛
    [ "$convergence" = converged ] || zh_convergence=未收敛
    cat > "$REPO/review-docs/pr-123-review.en.md" <<EOF
# Code Review — PR #123: fixture
| | |
|---|---|
| PR head | \`$head\` on \`feature\` of \`fork\` |
| Verdict | **$verdict** |
| Rounds | $rounds of max 3, $convergence |
### F-01 · fixture
- **Severity**: $severity
- **Where**: \`src/Foo.java:1\`
EOF
    cat > "$REPO/review-docs/pr-123-review.zh.md" <<EOF
# 代码评审 — PR #123：fixture
| | |
|---|---|
| PR head | \`$head\`，来自 \`fork\` 的 \`feature\` |
| 结论 | **$verdict** |
| 轮次 | 共 $rounds 轮（上限 3），$zh_convergence |
### F-01 · fixture
- **等级**：$severity
- **位置**：\`src/Foo.java:1\`
EOF
}

cat > "$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = api ] && [ "$2" = repos/apache/doris/pulls/123 ]; then
    printf '%s\topen\n' "${MOCK_LIVE_HEAD:?}"
elif [ "$1" = api ] && [ "$2" = user ]; then
    printf 'reviewer-one\n'
elif [ "$1" = api ] && [ "$2" = repos/apache/doris/issues/123/comments ]; then
    [ "${MOCK_COMMENT_LIST_FAIL:-0}" = 1 ] && exit 1
    [ "${MOCK_SAME_COMMENT:-0}" = 1 ] && printf '987\treviewer-one\tcommit: %s\n' "${MOCK_LIVE_HEAD:?}"
    exit 0
elif [ "$1" = api ] && [ "$2" = --method ]; then
    printf '%s\n' "$*" >> "${MOCK_GH_LOG:?}"
    cat > "${MOCK_GH_BODY:?}"
    printf '{"html_url":"https://github.com/apache/doris/pull/123#issuecomment-test"}\n'
else
    echo "unexpected gh invocation: $*" >&2
    exit 1
fi
EOF
chmod +x "$TMP_ROOT/bin/gh"
export PATH="$TMP_ROOT/bin:$PATH"
export MOCK_GH_LOG="$TMP_ROOT/gh.log"
export MOCK_GH_BODY="$TMP_ROOT/body.json"
export MOCK_LIVE_HEAD="$HEAD_SHA"

write_meta "$HEAD_SHA"
write_docs "$HEAD_SHA" APPROVE Minor 2 converged
expect_failure "poster requires runtime attestation" "review-runtime.json not found" \
    "$S/post-pass-comment.sh" --ctx "$CTX" --dry-run
"$S/record-review-runtime.sh" --ctx "$CTX" --model gpt-6-astra --effort xhigh >/dev/null

"$S/post-pass-comment.sh" --ctx "$CTX" --dry-run > "$TMP_ROOT/dry-run"
grep -Fq "commit: $HEAD_SHA" "$CTX/pr-comment.md" || fail "receipt commit is wrong"
grep -Fq "model: gpt-6-astra" "$CTX/pr-comment.md" || fail "receipt model is wrong"
grep -Fq "findings: {blocker: 0, major: 0, minor: 1, nit: 0}" "$CTX/pr-comment.md" \
    || fail "receipt findings are wrong"
[ -z "${RECEIPT_OUTPUT:-}" ] || cp "$CTX/pr-comment.md" "$RECEIPT_OUTPUT"
pass "verified dry run renders a pipeline-compatible receipt"

: > "$MOCK_GH_LOG"
MOCK_SAME_COMMENT=0 "$S/post-pass-comment.sh" --ctx "$CTX" > "$TMP_ROOT/create"
grep -Fq -- "--method POST repos/apache/doris/issues/123/comments --input -" "$MOCK_GH_LOG" \
    || fail "poster did not create a comment"
pass "qualified PASS creates a comment"

: > "$MOCK_GH_LOG"
MOCK_SAME_COMMENT=1 "$S/post-pass-comment.sh" --ctx "$CTX" > "$TMP_ROOT/update"
grep -Fq -- "--method PATCH repos/apache/doris/issues/comments/987 --input -" "$MOCK_GH_LOG" \
    || fail "poster did not update the same-commit comment"
pass "same-commit rerun updates the comment"

MOCK_COMMENT_LIST_FAIL=1 expect_failure "comment lookup failure stops posting" \
    "cannot list existing review comments" "$S/post-pass-comment.sh" --ctx "$CTX" --dry-run

BAD_NOTES="$TMP_ROOT/bad-notes.md"
printf 'not a bullet' > "$BAD_NOTES"
expect_failure "unterminated malformed note is rejected" "every note line" \
    "$S/post-pass-comment.sh" --ctx "$CTX" --notes-file "$BAD_NOTES" --dry-run

write_docs "$HEAD_SHA" REQUEST_CHANGES Major 2 converged
expect_failure "REQUEST_CHANGES never posts" "verdict is REQUEST_CHANGES" \
    "$S/post-pass-comment.sh" --ctx "$CTX" --dry-run

write_docs "$HEAD_SHA" APPROVE Minor 3 'did not converge'
expect_failure "non-converged review never posts" "did not converge" \
    "$S/post-pass-comment.sh" --ctx "$CTX" --dry-run

write_docs "$HEAD_SHA" APPROVE Minor 2 converged
MOCK_LIVE_HEAD="$OTHER_SHA" expect_failure "moved PR head invalidates review" "PR head moved" \
    "$S/post-pass-comment.sh" --ctx "$CTX" --dry-run

write_meta "$OTHER_SHA"
MOCK_LIVE_HEAD="$OTHER_SHA" expect_failure "runtime attestation is commit-bound" "was recorded for" \
    "$S/post-pass-comment.sh" --ctx "$CTX" --dry-run

echo "$PASS_COUNT post-comment tests passed"
