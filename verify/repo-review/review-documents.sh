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
printf 'int answer = 42;\nint other = 7;\n' > "$REPO/src/Foo.java"
printf 'src/Foo.java\t1\t2\n' > "$CTX/changed_line_ranges.tsv"

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

# EN_REGRESSION / ZH_REGRESSION: the value of the mandatory regression line (default no / 否);
# EN_CATEGORY / ZH_CATEGORY: the value of the mandatory category line (default a floored one);
# EN_RATIONALE / ZH_RATIONALE: an optional "Severity rationale" paragraph.
# The literal word `omit` leaves the line out entirely.
EN_REGRESSION="${EN_REGRESSION:-no}"
ZH_REGRESSION="${ZH_REGRESSION:-否}"
EN_CATEGORY="${EN_CATEGORY:-functional-loss}"
ZH_CATEGORY="${ZH_CATEGORY:-功能缺失}"
EN_RATIONALE="${EN_RATIONALE:-omit}"
ZH_RATIONALE="${ZH_RATIONALE:-omit}"

finding_line() {
    local label="$1" value="$2"
    [ "$value" = omit ] || printf -- '- **%s**%s\n' "$label" "$value"
}

rationale_paragraph() {
    local label="$1" value="$2"
    [ "$value" = omit ] || printf -- '\n**%s** %s\n' "$label" "$value"
}

write_docs() {
    local head="$1" verdict="$2" en_severity="$3" zh_severity="$4"
    local rounds="$5" en_convergence="$6" zh_convergence="$7"
    local en_anchor="${8:-1}"
    local zh_anchor="${9:-$en_anchor}"
    local en_max="${10:-3}"
    local zh_max="${11:-$en_max}"
    cat > "$REPO/review-docs/pr-123-review.en.md" <<EOF
# Code Review — PR #123: fixture

| | |
|---|---|
| PR head | \`$head\` on \`feature\` of \`fork\` |
| Verdict | **$verdict** |
| Rounds | $rounds of max $en_max; $en_convergence |

## Findings

### F-01 · fixture finding

- **Severity**: $en_severity
$(finding_line Category ": $EN_CATEGORY")
$(finding_line Regression ": $EN_REGRESSION")
- **Where**: \`src/Foo.java:$en_anchor\`
$(rationale_paragraph "Severity rationale." "$EN_RATIONALE")
EOF
    cat > "$REPO/review-docs/pr-123-review.zh.md" <<EOF
# 代码评审 — PR #123：fixture

| | |
|---|---|
| PR head | \`$head\`，来自 \`fork\` 的 \`feature\` |
| 结论 | **$verdict** |
| 轮次 | 共 ${rounds} 轮（上限 ${zh_max}）；${zh_convergence} |

## 问题清单

### F-01 · fixture finding

- **等级**：$zh_severity
$(finding_line 类别 "：$ZH_CATEGORY")
$(finding_line 回归 "：$ZH_REGRESSION")
- **位置**：\`src/Foo.java:$zh_anchor\`
$(rationale_paragraph "定级理由。" "$ZH_RATIONALE")
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
    '.commit == $head and .verdict == "APPROVE" and .findings.minor == 1 and .regressions == 0 and .floored_regressions == 0 and .rounds == 2 and .converged' \
    <<<"$RESULT" >/dev/null || fail "verified result JSON is wrong"
pass "matching documents produce one verified result"

# ---- category-aware regression floor
for category in "functional-bug 功能缺陷" "functional-loss 功能缺失" "data-error 数据错误" \
                "resource-leak 资源泄露" "performance 性能降低"; do
    set -- $category
    EN_CATEGORY="$1" ZH_CATEGORY="$2" EN_REGRESSION=yes ZH_REGRESSION=是 \
        write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
    expect_failure "a $1 regression cannot be rated Minor" "a $1 regression against the merge base is at least Major" verify_json
done

EN_REGRESSION=yes ZH_REGRESSION=是 write_docs "$HEAD_SHA" APPROVE Nit Nit 2 converged 已收敛
expect_failure "a floored regression cannot be rated Nit" "at least Major" verify_json

EN_REGRESSION=yes ZH_REGRESSION=是 write_docs "$HEAD_SHA" REQUEST_CHANGES Major Major 2 converged 已收敛
RESULT="$(verify_json)"
jq -e '.verdict == "REQUEST_CHANGES" and .findings.major == 1 and .regressions == 1 and .floored_regressions == 1' <<<"$RESULT" >/dev/null \
    || fail "regression counts are not reported"
pass "a Major floored regression is counted in the verified result"

EN_CATEGORY=observability ZH_CATEGORY=可观测性 EN_REGRESSION=yes ZH_REGRESSION=是 \
    write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "a non-floored regression below Major needs a rationale" \
    "add a **Severity rationale** paragraph" verify_json

for category in "observability 可观测性" "test-coverage 测试覆盖" "wording 措辞" "maintainability 可维护性"; do
    set -- $category
    EN_CATEGORY="$1" ZH_CATEGORY="$2" EN_REGRESSION=yes ZH_REGRESSION=是 \
        EN_RATIONALE="only troubleshooting convenience is affected." ZH_RATIONALE="只影响排障便利性。" \
        write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
    RESULT="$(verify_json)"
    jq -e '.verdict == "APPROVE" and .findings.minor == 1 and .regressions == 1 and .floored_regressions == 0' <<<"$RESULT" >/dev/null \
        || fail "a $1 regression with a rationale was not accepted at Minor"
    pass "a $1 regression with a rationale may stay Minor"
done

EN_CATEGORY='functional-bug (concurrency: lock order)' ZH_CATEGORY='功能缺陷（并发：锁序）' \
    EN_REGRESSION=yes ZH_REGRESSION=是 write_docs "$HEAD_SHA" REQUEST_CHANGES Major Major 2 converged 已收敛
RESULT="$(verify_json)"
jq -e '.floored_regressions == 1' <<<"$RESULT" >/dev/null || fail "a domain note after the category was not accepted"
pass "a parenthetical domain note after the category is accepted"

EN_CATEGORY='Functional Bug' ZH_CATEGORY='功能性 bug' EN_REGRESSION=yes ZH_REGRESSION=是 \
    write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "category spelling variants still resolve to the floored class" \
    "a functional-bug regression against the merge base is at least Major" verify_json

EN_CATEGORY=omit write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "the category line is mandatory" "has no Category/类别 line" verify_json

EN_CATEGORY=security ZH_CATEGORY=安全 write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "an unknown category is rejected" "unknown category 'security'" verify_json

EN_CATEGORY=observability ZH_CATEGORY=功能缺失 write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "EN and ZH categories must agree" "categories differ" verify_json

EN_REGRESSION='no (base 699-701 already lacked the reset)' ZH_REGRESSION='否（base 本来就没有）' \
    write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
RESULT="$(verify_json)"
jq -e '.regressions == 0' <<<"$RESULT" >/dev/null || fail "annotated regression flag was not accepted"
pass "a parenthetical note after the regression flag is accepted"

EN_REGRESSION=omit write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "the regression line is mandatory" "has no Regression/回归 line" verify_json

EN_REGRESSION=yes ZH_REGRESSION=否 write_docs "$HEAD_SHA" REQUEST_CHANGES Major Major 2 converged 已收敛
expect_failure "EN and ZH regression flags must agree" "regression flags differ" verify_json

EN_REGRESSION=maybe write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "an unparseable regression value is rejected" "has no Regression/回归 line" verify_json

write_docs "$OTHER_SHA" APPROVE Minor Minor 2 converged 已收敛
expect_failure "document commit must match context" "context head" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Nit 2 converged 已收敛
expect_failure "EN and ZH severities must agree" "severities differ" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛 1 2
expect_failure "EN and ZH anchors must agree" "anchors differ" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 4 converged 已收敛
expect_failure "rounds must stay within the cap" "between 1 and 3" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛 3
expect_failure "anchors must resolve" "out of range" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 2 converged 已收敛 2-1
expect_failure "anchor ranges cannot run backwards" "end before its start" verify_json

write_docs "$HEAD_SHA" REQUEST_CHANGES Major Major 2 converged 已收敛
RESULT="$(verify_json)"
jq -e '.verdict == "REQUEST_CHANGES" and .findings.major == 1' <<<"$RESULT" >/dev/null \
    || fail "REQUEST_CHANGES result is wrong"
pass "Major findings produce REQUEST_CHANGES"

write_docs "$HEAD_SHA" APPROVE Minor Minor 3 'did not converge' 未收敛
RESULT="$(verify_json)"
jq -e '.converged == false' <<<"$RESULT" >/dev/null || fail "non-convergence was not preserved"
pass "documented non-converged result remains explicit"

write_docs "$HEAD_SHA" APPROVE Minor Minor 2 \
    'converged (verdict stable since round 1)' '已收敛（结论自第 1 轮起稳定）'
RESULT="$(verify_json)"
jq -e '.rounds == 2 and .converged == true' <<<"$RESULT" >/dev/null \
    || fail "annotated convergence was not preserved"
pass "documented convergence notes are accepted"

write_docs "$HEAD_SHA" APPROVE Minor Minor 3 unconverged 已收敛
expect_failure "convergence substring is rejected" "missing Rounds/轮次 value" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 3 not-converged 已收敛
expect_failure "hyphenated negative is not certified as converged" \
    "missing Rounds/轮次 value" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 3 converged '尚未达到已收敛状态'
expect_failure "Chinese negative prose is not certified as converged" \
    "missing Rounds/轮次 value" verify_json

write_docs "$HEAD_SHA" APPROVE Minor Minor 3 converged 已收敛 1 1 30 30
expect_failure "malformed maximum is rejected" "missing Rounds/轮次 value" verify_json

echo "$PASS_COUNT review-document tests passed"
