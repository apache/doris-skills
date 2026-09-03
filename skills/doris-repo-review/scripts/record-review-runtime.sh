#!/usr/bin/env bash
# Record the qualified reviewer model, effort, and reviewed commit.
set -euo pipefail

CTX=""
MODEL=""
EFFORT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ctx) CTX="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --effort) EFFORT="$2"; shift 2 ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$CTX" ] || { echo "ERROR: --ctx is required." >&2; exit 2; }
[ -n "$MODEL" ] || { echo "ERROR: --model is required." >&2; exit 2; }
[ -n "$EFFORT" ] || { echo "ERROR: --effort is required." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }

META="$CTX/meta.env"
[ -f "$META" ] || { echo "ERROR: $META not found - run prepare-review-context.sh first." >&2; exit 2; }
HEAD_SHA="$(sed -n 's/^HEAD_SHA=//p' "$META" | head -n 1)"
[[ "$HEAD_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "ERROR: meta.env HEAD_SHA is not a full SHA." >&2; exit 2; }
NORMALIZED_HEAD_SHA="$(printf '%s' "$HEAD_SHA" | tr '[:upper:]' '[:lower:]')"

RUNTIME_FILE="$CTX/review-runtime.json"
rm -f "$RUNTIME_FILE" "$CTX/pr-comment.md" "$CTX/pr-comment.url"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=review-runtime-policy.sh
. "$SCRIPT_DIR/review-runtime-policy.sh"
check_review_runtime "$MODEL" "$EFFORT"

TMP_FILE="$(mktemp "$CTX/.review-runtime.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT
jq -n --arg model "$MODEL" --arg effort "$EFFORT" --arg commit "$NORMALIZED_HEAD_SHA" \
    '{model: $model, effort: $effort, commit: $commit}' > "$TMP_FILE"
mv "$TMP_FILE" "$RUNTIME_FILE"
trap - EXIT

echo "recorded qualified review runtime: $MODEL ($EFFORT), commit $NORMALIZED_HEAD_SHA"
