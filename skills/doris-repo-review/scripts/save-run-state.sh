#!/usr/bin/env bash
# Persist what this run concluded, so the next review of the same PR starts from
# it instead of from zero (`doris-repo-review` skill, step 11).
#
# What gets kept is the merged ledger - and the expensive part of that is the
# "Considered and Dismissed" set, with its evidence. A later run reads it back
# through <ctx>/prior_runs/ and carries the dismissals forward rather than
# re-deriving them, which is also what makes "was this considered last time?"
# an answerable question.
#
# Usage:
#   save-run-state.sh --ctx <dir> --verdict <APPROVE|REQUEST_CHANGES> \
#                     --findings <blocker>,<major>,<minor>,<nit> \
#                     --rounds <n> --converged <true|false> \
#                     [--docs <path>[,<path>]] [--note <text>]
#
# Writes <state>/runs/<head7>/{main-merged.md,meta.env} and appends <state>/index.tsv,
# where <state> is the STATE_DIR recorded in <ctx>/meta.env by prepare-review-context.sh.
set -euo pipefail

CTX=""; VERDICT=""; FINDINGS=""; ROUNDS=""; CONVERGED=""; DOCS=""; NOTE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ctx)       CTX="$2"; shift 2 ;;
        --verdict)   VERDICT="$2"; shift 2 ;;
        --findings)  FINDINGS="$2"; shift 2 ;;
        --rounds)    ROUNDS="$2"; shift 2 ;;
        --converged) CONVERGED="$2"; shift 2 ;;
        --docs)      DOCS="$2"; shift 2 ;;
        --note)      NOTE="$2"; shift 2 ;;
        -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$CTX" ] || { echo "ERROR: --ctx is required" >&2; exit 2; }
[ -f "$CTX/meta.env" ] || { echo "ERROR: $CTX/meta.env not found" >&2; exit 2; }

read_meta() { sed -n "s/^$1=//p" "$CTX/meta.env" | head -n 1; }
STATE_DIR="$(read_meta STATE_DIR)"
HEAD_SHA="$(read_meta HEAD_SHA)"
PR_NUMBER="$(read_meta PR_NUMBER)"
REVIEW_DATE="$(read_meta REVIEW_DATE)"

if [ -z "$STATE_DIR" ]; then
    echo "No STATE_DIR in meta.env (the PR number was not resolved), so this run cannot be saved." >&2
    echo "That is not fatal - it only means the next review starts without this one's dismissals." >&2
    exit 0
fi
[ -n "$VERDICT" ]   || { echo "ERROR: --verdict is required" >&2; exit 2; }
[ -n "$FINDINGS" ]  || { echo "ERROR: --findings is required" >&2; exit 2; }
[ -n "$ROUNDS" ]    || { echo "ERROR: --rounds is required" >&2; exit 2; }
[ -n "$CONVERGED" ] || { echo "ERROR: --converged is required" >&2; exit 2; }
case "$VERDICT" in APPROVE|REQUEST_CHANGES) ;; *) echo "ERROR: bad --verdict: $VERDICT" >&2; exit 2 ;; esac
case "$CONVERGED" in true|false) ;; *) echo "ERROR: --converged must be true or false" >&2; exit 2 ;; esac
echo "$FINDINGS" | grep -Eq '^[0-9]+,[0-9]+,[0-9]+,[0-9]+$' \
    || { echo "ERROR: --findings must be <blocker>,<major>,<minor>,<nit>" >&2; exit 2; }

HEAD7="${HEAD_SHA:0:7}"
RUN_DIR="$STATE_DIR/runs/$HEAD7"
mkdir -p "$RUN_DIR"

if [ -f "$CTX/ledger/main-merged.md" ]; then
    cp "$CTX/ledger/main-merged.md" "$RUN_DIR/main-merged.md"
else
    echo "WARNING: no $CTX/ledger/main-merged.md to save - the next run inherits nothing." >&2
fi
cp "$CTX/meta.env" "$RUN_DIR/meta.env"
[ -f "$CTX/coverage_report.txt" ] && cp "$CTX/coverage_report.txt" "$RUN_DIR/coverage_report.txt"

INDEX="$STATE_DIR/index.tsv"
[ -f "$INDEX" ] || printf 'date\thead\tverdict\tblocker,major,minor,nit\trounds\tconverged\tdocs\tnote\n' > "$INDEX"
# One row per head. Re-running against an unchanged head replaces its row.
if grep -q "	${HEAD7}	" "$INDEX" 2>/dev/null; then
    grep -v "	${HEAD7}	" "$INDEX" > "$INDEX.tmp" && mv "$INDEX.tmp" "$INDEX"
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${REVIEW_DATE:-$(date +%Y-%m-%d)}" "$HEAD7" "$VERDICT" "$FINDINGS" \
    "$ROUNDS" "$CONVERGED" "${DOCS:-}" "${NOTE:-}" >> "$INDEX"

echo "saved run state for PR #${PR_NUMBER:-?} head $HEAD7"
echo "  $RUN_DIR"
echo "  $INDEX"
echo
echo "history for this PR:"
column -t -s '	' "$INDEX" 2>/dev/null || cat "$INDEX"
