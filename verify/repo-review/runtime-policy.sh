#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="$ROOT/skills/doris-repo-review/scripts/review-runtime-policy.sh"
PASS_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $1"
}

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# shellcheck source=/dev/null
. "$POLICY"

for model in claude-opus-5 'claude-opus-5[1m]' claude-fable-5 'claude-fable-5[1m]' gpt-5.6-sol; do
    is_eligible_review_model "$model" || fail "eligible model rejected: $model"
done
pass "exact model allowlist is accepted"

for model in claude-opus-5.1 claude-fable-4 gpt-5.6-terra gpt-5.7-sol unknown; do
    if is_eligible_review_model "$model"; then
        fail "unlisted model accepted: $model"
    fi
done
pass "unlisted models are rejected"

for model in claude-opus-5 'claude-opus-5[1m]' claude-fable-5 'claude-fable-5[1m]'; do
    for effort in xhigh max; do
        is_eligible_review_effort "$model" "$effort" \
            || fail "eligible Claude runtime rejected: $model ($effort)"
    done
done
pass "Claude models accept their supported qualified efforts"

for model in claude-opus-5 'claude-opus-5[1m]' claude-fable-5 'claude-fable-5[1m]'; do
    if is_eligible_review_effort "$model" ultra; then
        fail "unsupported Claude ultra effort accepted: $model"
    fi
done
pass "Claude models reject unsupported ultra effort"

for effort in xhigh max ultra; do
    is_eligible_review_effort gpt-5.6-sol "$effort" \
        || fail "eligible Codex runtime rejected: gpt-5.6-sol ($effort)"
done
pass "Codex accepts xhigh, max, and ultra"

for model in claude-opus-5 gpt-5.6-sol; do
    for effort in minimal low medium high unknown; do
        if is_eligible_review_effort "$model" "$effort"; then
            fail "ineligible runtime accepted: $model ($effort)"
        fi
    done
done
pass "lower and unknown efforts are rejected for every host"

"$POLICY" check gpt-5.6-sol xhigh >/dev/null
if "$POLICY" check gpt-5.6-sol high >/dev/null 2>&1; then
    fail "policy CLI accepted high effort"
fi
if "$POLICY" check claude-opus-5 ultra >/dev/null 2>&1; then
    fail "policy CLI accepted unsupported Claude ultra effort"
fi
pass "policy CLI enforces model-specific effort allowlists"

echo "$PASS_COUNT runtime-policy tests passed"
