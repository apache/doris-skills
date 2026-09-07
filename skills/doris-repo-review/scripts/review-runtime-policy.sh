#!/usr/bin/env bash
# Exact reviewer allowlist for a pipeline-equivalent local Doris review.

is_eligible_review_model() {
    case "$1" in
        claude-opus-5|claude-opus-5\[1m\]|claude-fable-5|claude-fable-5\[1m\]|claude-fable-5-1|claude-fable-5-1\[1m\]|gpt-5.6-sol|gpt-6-astra) return 0 ;;
        *) return 1 ;;
    esac
}

is_eligible_review_effort() {
    local model="$1"
    local effort="$2"
    case "$model" in
        claude-opus-5|claude-opus-5\[1m\]|claude-fable-5|claude-fable-5\[1m\]|claude-fable-5-1|claude-fable-5-1\[1m\])
            case "$effort" in
                xhigh|max) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        gpt-5.6-sol|gpt-6-astra)
            case "$effort" in
                xhigh|max|ultra) return 0 ;;
                *) return 1 ;;
            esac
            ;;
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
    is_eligible_review_effort "$model" "$effort" || {
        echo "ERROR: effort '$effort' is not eligible for model '$model'." >&2
        echo "       Claude Code supports xhigh or max; Codex also supports ultra." >&2
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
