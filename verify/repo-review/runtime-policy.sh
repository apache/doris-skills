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

for model in claude-opus-5-5 'claude-opus-5-5[1m]' claude-fable-5 'claude-fable-5[1m]' claude-fable-5-1 'claude-fable-5-1[1m]' gpt-6.2-sol gpt-6.2-astra gpt-6.1-sol gpt-6-sol gpt-6-astra gemini-4-carbon gemini-4-neon; do
    is_eligible_review_model "$model" || fail "eligible model rejected: $model"
done
pass "exact model allowlist is accepted"

for model in claude-opus-4-8 'claude-opus-4-8[1m]' claude-opus-5.1 claude-fable-4 gpt-5.6 gpt-5.6-terra gpt-5.6-luna gpt-5.7-sol gpt-6.1 gpt-6.1-sol-preview 'gpt-6.1-sol[1m]' gpt-6.2 gpt-6.2-astra-preview 'gpt-6.2-sol[1m]' gpt-6 gemini-4 gemini-4-carbon-high gemini-4-neon-xhigh gemini-4-argon gemini-4-hydrogen gemini-pro-orchestrator gemini-pro-orchestrator-neon unknown; do
    if is_eligible_review_model "$model"; then
        fail "unlisted model accepted: $model"
    fi
done
pass "unlisted models are rejected"

for model in gpt-5.6-sol claude-opus-5 'claude-opus-5[1m]'; do
    if is_eligible_review_model "$model"; then
        fail "retired model accepted: $model"
    fi
    for effort in xhigh max ultra; do
        if is_eligible_review_effort "$model" "$effort"; then
            fail "retired model effort accepted: $model ($effort)"
        fi
        if "$POLICY" check "$model" "$effort" >/dev/null 2>&1; then
            fail "policy CLI accepted retired model: $model ($effort)"
        fi
    done
done
pass "retired models are rejected by the policy and CLI"

for model in claude-opus-5-5 'claude-opus-5-5[1m]' claude-fable-5 'claude-fable-5[1m]' claude-fable-5-1 'claude-fable-5-1[1m]'; do
    for effort in xhigh max; do
        is_eligible_review_effort "$model" "$effort" \
            || fail "eligible Claude runtime rejected: $model ($effort)"
    done
done
pass "Claude models accept their supported qualified efforts"

for model in claude-opus-5-5 'claude-opus-5-5[1m]' claude-fable-5 'claude-fable-5[1m]' claude-fable-5-1 'claude-fable-5-1[1m]'; do
    if is_eligible_review_effort "$model" ultra; then
        fail "unsupported Claude ultra effort accepted: $model"
    fi
done
pass "Claude models reject unsupported ultra effort"

for model in gpt-6.2-sol gpt-6.2-astra gpt-6.1-sol gpt-6-sol gpt-6-astra; do
    for effort in xhigh max ultra; do
        is_eligible_review_effort "$model" "$effort" \
            || fail "eligible Codex runtime rejected: $model ($effort)"
    done
done
pass "Codex accepts xhigh, max, and ultra"

is_eligible_review_effort gemini-4-carbon high \
    || fail "eligible Gemini Carbon runtime rejected: gemini-4-carbon (high)"
is_eligible_review_effort gemini-4-neon xhigh \
    || fail "eligible Gemini Neon runtime rejected: gemini-4-neon (xhigh)"
for effort in none minimal low medium xhigh max ultra unknown ''; do
    if is_eligible_review_effort gemini-4-carbon "$effort"; then
        fail "ineligible Gemini Carbon runtime accepted: gemini-4-carbon ($effort)"
    fi
done
for effort in max ultra; do
    if is_eligible_review_effort gemini-4-neon "$effort"; then
        fail "unsupported Gemini Neon effort accepted: gemini-4-neon ($effort)"
    fi
done
pass "Antigravity Gemini 4 models enforce exact per-model efforts"

for model in claude-opus-5-5 'claude-opus-5-5[1m]' claude-fable-5 'claude-fable-5[1m]' claude-fable-5-1 'claude-fable-5-1[1m]' gpt-6.2-sol gpt-6.2-astra gpt-6.1-sol gpt-6-sol gpt-6-astra gemini-4-neon; do
    for effort in none minimal low medium high unknown ''; do
        if is_eligible_review_effort "$model" "$effort"; then
            fail "ineligible runtime accepted: $model ($effort)"
        fi
    done
done
pass "lower and unknown efforts are rejected for xhigh-minimum models"

"$POLICY" check gpt-6.2-astra xhigh >/dev/null
"$POLICY" check gpt-6.2-sol ultra >/dev/null
"$POLICY" check gpt-6.1-sol xhigh >/dev/null
"$POLICY" check gemini-4-carbon high >/dev/null
"$POLICY" check gemini-4-neon xhigh >/dev/null
if "$POLICY" check gpt-6.1-sol high >/dev/null 2>&1; then
    fail "policy CLI accepted high effort for gpt-6.1-sol"
fi
if "$POLICY" check gpt-6.2-sol high >/dev/null 2>&1; then
    fail "policy CLI accepted high effort for gpt-6.2-sol"
fi
if "$POLICY" check gemini-4-neon high >/dev/null 2>&1; then
    fail "policy CLI accepted high effort for gemini-4-neon"
fi
if "$POLICY" check gemini-4-carbon xhigh >/dev/null 2>&1; then
    fail "policy CLI accepted unsupported xhigh effort for gemini-4-carbon"
fi
if "$POLICY" check claude-opus-5-5 ultra >/dev/null 2>&1; then
    fail "policy CLI accepted unsupported Claude ultra effort"
fi
pass "policy CLI enforces model-specific effort allowlists"

echo "$PASS_COUNT runtime-policy tests passed"
