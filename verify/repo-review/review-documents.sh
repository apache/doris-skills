#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERIFIER="$ROOT/skills/doris-repo-review/scripts/verify-review-docs.py"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/doris-review-docs.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
REPO="$TMP_ROOT/repo"
CTX="$TMP_ROOT/ctx"
HEAD_SHA="1111111111111111111111111111111111111111"
OTHER_SHA="3333333333333333333333333333333333333333"
PASS_COUNT=0
mkdir -p "$REPO/src" "$REPO/review-docs" "$CTX"
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
    grep -Fq "$pattern" "$TMP_ROOT/err" || fail "$label failed for the wrong reason"
    pass "$label"
}

write_meta() {
    cat > "$CTX/meta.env" <<EOF
PR_NUMBER=123
HEAD_SHA=$1
REPO_ROOT=$REPO
DOCS_ROOT=$REPO
EOF
}

write_docs() {
    local head="$1" verdict="$2" en_severity="$3" zh_severity="$4"
    local rounds="$5" en_convergence="$6" zh_convergence="$7" anchor="${8:-1}"
    cat > "$REPO/review-docs/pr-123-review.en.md" <<EOF
# Code Review — PR #123: fixture

| | |
|---|---|
| PR head | \`$head\` on \`feature\` of \`fork\` |
| Verdict | **$verdict** |
| Rounds | $rounds of max 3, $en_convergence |

## Findings

### F-01 · fixture finding

- **Severity**: $en_severity
- **Where**: \`src/Foo.java:$anchor\`
EOF
    cat > "$REPO/review-docs/pr-123-review.zh.md" <<EOF
# 代码评审 — PR #123：fixture

| | |
|---|---|
| PR head | \`$head\`，来自 \`fork\` 的 \`feature\` |
| 结论 | **$verdict** |
| 轮次 | 共 $rounds 轮（上限 3），$zh_convergence |

## 问题清单

### F-01 · fixture finding

- **等级**：$zh_severity
- **位置**：\`src/Foo.java:$anchor\`
EOF
}

verify_json() {
    "$VERIFIER" --json --ctx "$CTX" \
        --doc "$REPO/review-docs/pr-123-review.en.md" \
        --doc "$REPO/review-docs/pr-123-review.zh.md"
}

write_meta "$HEAD_SHA"
write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
RESULT="$(verify_json)"
jq -e --arg head "$HEAD_SHA" \
    '.commit == $head and .verdict == "APPROVE" and .findings.minor == 1 and .rounds == 2 and .converged' \
    <<<"$RESULT" >/dev/null || fail "verified result JSON is wrong"
pass "matching documents produce one verified result"

write_docs "$OTHER_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "document commit must match context" "context head" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Nit 2 converged 已收敛
expect_failure "EN and ZH severities must agree" "severities differ" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 4 converged 已收敛
expect_failure "rounds must stay within the cap" "between 1 and 3" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛 2
expect_failure "anchors must resolve" "out of range" verify_json

write_docs "$HEAD_SHA" REQUEST_CHANGES Major Major 2 converged 已收敛
RESULT="$(verify_json)"
jq -e '.verdict == "REQUEST_CHANGES" and .findings.major == 1' <<<"$RESULT" >/dev/null \
    || fail "REQUEST_CHANGES result is wrong"
pass "Major findings produce REQUEST_CHANGES"

write_docs "$HEAD_SHA" APPROVE Minor Minor 3 'not converged' 未收敛
RESULT="$(verify_json)"
jq -e '.converged == false' <<<"$RESULT" >/dev/null || fail "non-convergence was not preserved"
pass "non-converged result remains explicit"

echo "$PASS_COUNT review-document tests passed"
