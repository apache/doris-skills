#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RECORDER="$ROOT/skills/doris-repo-review/scripts/record-review-runtime.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/doris-review-runtime.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
HEAD_SHA="1111111111111111111111111111111111111111"
PASS_COUNT=0

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
    mkdir -p "$1"
    printf 'HEAD_SHA=%s\n' "$2" > "$1/meta.env"
}

CTX="$TMP_ROOT/ctx"
write_meta "$CTX" "$HEAD_SHA"
"$RECORDER" --ctx "$CTX" --model gpt-6-sol --effort xhigh >/dev/null
jq -e --arg head "$HEAD_SHA" \
    '.model == "gpt-6-sol" and .effort == "xhigh" and .commit == $head' \
    "$CTX/review-runtime.json" >/dev/null || fail "runtime JSON fields are wrong"
pass "qualified runtime records model, effort, and commit"

expect_failure "low effort is rejected" "not eligible for model 'gpt-6-sol'" \
    "$RECORDER" --ctx "$CTX" --model gpt-6-sol --effort high
[ ! -e "$CTX/review-runtime.json" ] || fail "failed replacement left an old runtime record"
pass "failed replacement removes the old attestation"

expect_failure "Claude ultra effort is rejected" "not eligible for model 'claude-opus-5-5'" \
    "$RECORDER" --ctx "$CTX" --model claude-opus-5-5 --effort ultra

"$RECORDER" --ctx "$CTX" --model claude-opus-5-5 --effort max >/dev/null
jq -e --arg head "$HEAD_SHA" \
    '.model == "claude-opus-5-5" and .effort == "max" and .commit == $head' \
    "$CTX/review-runtime.json" >/dev/null || fail "supported Claude runtime was not recorded"
pass "supported Claude effort is recorded"

expect_failure "unlisted model is rejected" "is not eligible" \
    "$RECORDER" --ctx "$CTX" --model gpt-5.6-terra --effort xhigh

for model in gpt-5.6-sol claude-opus-5 'claude-opus-5[1m]'; do
    "$RECORDER" --ctx "$CTX" --model gpt-6-sol --effort xhigh >/dev/null
    expect_failure "retired model is rejected: $model" "is not eligible" \
        "$RECORDER" --ctx "$CTX" --model "$model" --effort xhigh
    [ ! -e "$CTX/review-runtime.json" ] || fail "retired replacement left an old runtime record"
done

BAD_CTX="$TMP_ROOT/bad-ctx"
write_meta "$BAD_CTX" deadbeef
expect_failure "short commit is rejected" "not a full SHA" \
    "$RECORDER" --ctx "$BAD_CTX" --model gpt-6-sol --effort xhigh

echo "$PASS_COUNT runtime-attestation tests passed"
