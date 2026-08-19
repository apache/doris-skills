#!/usr/bin/env bash
# Exact reviewer allowlist for a pipeline-equivalent local Doris review.

is_eligible_review_model() {
    case "$1" in
        claude-opus-5|claude-opus-5\[1m\]|claude-fable-5|claude-fable-5\[1m\]|gpt-5.6-sol) return 0 ;;
        *) return 1 ;;
    esac
}

is_eligible_review_effort() {
    case "$1" in
        xhigh|max|ultra) return 0 ;;
        *) return 1 ;;
    esac
}

check_review_runtime() {
    local model="$1"
    local effort="$2"
    is_eligible_review_model "$model" || {
        echo "ERROR: model '$model' is not eligible for pipeline-equivalent review." >&2
        return 1
    }
    is_eligible_review_effort "$effort" || {
        echo "ERROR: effort '$effort' is not eligible; use xhigh or higher." >&2
        return 1
    }
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    [ "${1:-}" = "check" ] && [ $# -eq 3 ] || {
        echo "usage: $0 check <model> <effort>" >&2
        exit 2
    }
    check_review_runtime "$2" "$3"
    echo "eligible review runtime: $2 ($3)"
fi
