#!/usr/bin/env bash
# Mechanical coverage report for the `doris-repo-review` skill (step 6a).
#
# Answers one question, with grep rather than judgement: which of this PR's
# changed files has no ledger file so much as mentioned yet?
#
# A file nobody read is not a file with no findings. Running this after every
# round is what lets the next round be aimed instead of guessed, and what keeps
# "13 changed files nobody opened" from being a round-3 discovery.
#
# Usage:
#   coverage-report.sh --ctx <dir> [--round <n>] [--quiet]
#
# Reads  : <ctx>/pr_changed_files.txt, <ctx>/ledger/*.md
# Writes : <ctx>/coverage_report.txt  (and appends one line to <ctx>/coverage_history.tsv)
# Exit   : 0 when every changed file is mentioned, 1 when some are not.
set -euo pipefail

CTX=""
ROUND=""
QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --ctx)   CTX="$2"; shift 2 ;;
        --round) ROUND="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$CTX" ] || { echo "ERROR: --ctx is required" >&2; exit 2; }
[ -d "$CTX" ] || { echo "ERROR: no such context directory: $CTX" >&2; exit 2; }
CHANGED="$CTX/pr_changed_files.txt"
[ -f "$CHANGED" ] || { echo "ERROR: $CHANGED not found - run prepare-review-context.sh first" >&2; exit 2; }

python3 - "$CTX" "${ROUND:-}" "$QUIET" <<'PY'
import os, sys, glob, datetime

ctx, round_label, quiet = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
changed = [l.strip() for l in open(os.path.join(ctx, "pr_changed_files.txt")) if l.strip()]

ledger_files = sorted(
    p for p in glob.glob(os.path.join(ctx, "ledger", "*.md"))
    # main-merged is the main agent's own summary; the risk scan is written
    # before anyone reads anything. Neither is evidence that a file was read.
    if os.path.basename(p) not in ("README.md", "main-merged.md", "00-main-risk-scan.md")
)

blobs = {}
for p in ledger_files:
    try:
        blobs[os.path.basename(p)] = open(p, errors="replace").read()
    except OSError:
        pass

def mentions(path, text):
    """A file counts as mentioned when its full path or its basename appears."""
    if path in text:
        return True
    base = os.path.basename(path)
    # A bare basename is weak evidence for a common name (pom.xml, README.md),
    # so require the full path for those.
    return len(base) > 12 and base in text

unread, by_owner = [], {}
for path in changed:
    owners = [name for name, text in blobs.items() if mentions(path, text)]
    if owners:
        for o in owners:
            by_owner.setdefault(o, 0)
            by_owner[o] += 1
    else:
        unread.append(path)

lines = []
lines.append("=== coverage report ===")
lines.append(f"round          : {round_label or '(unspecified)'}")
lines.append(f"changed files  : {len(changed)}")
lines.append(f"mentioned      : {len(changed) - len(unread)}")
lines.append(f"NOT mentioned  : {len(unread)}")
lines.append(f"ledger files   : {len(blobs)}")
if by_owner:
    lines.append("")
    lines.append("files mentioned per ledger owner:")
    for name in sorted(by_owner):
        lines.append(f"  {by_owner[name]:4d}  {name}")
if unread:
    lines.append("")
    lines.append("changed files no ledger file mentions yet:")
    lines.extend("  " + p for p in unread)
    lines.append("")
    lines.append("These are not files with no findings - they are files nobody has read.")
    lines.append("Cover them in the next round's slicing, or read them yourself in step 8.")
else:
    lines.append("")
    lines.append("Every changed file is mentioned by at least one ledger file.")

report = "\n".join(lines) + "\n"
open(os.path.join(ctx, "coverage_report.txt"), "w").write(report)

hist = os.path.join(ctx, "coverage_history.tsv")
if not os.path.exists(hist):
    open(hist, "w").write("date\tround\tchanged\tmentioned\tunread\n")
with open(hist, "a") as f:
    f.write("%s\t%s\t%d\t%d\t%d\n" % (
        datetime.date.today().isoformat(), round_label or "-",
        len(changed), len(changed) - len(unread), len(unread)))

if not quiet:
    sys.stdout.write(report)
sys.exit(1 if unread else 0)
PY
