#!/usr/bin/env bash
# Prepare the authoritative local review context for the `doris-repo-review` skill.
#
# Mirrors the "Prepare authoritative PR context and required AGENTS guides" +
# "Fetch existing PR review threads" + "Prepare review prompt" steps of
# apache/doris .github/workflows/code-review-runner.yml, but sources the diff
# from the local worktree instead of a CI checkout.
#
# Usage:
#   prepare-review-context.sh [--ctx <dir>] [--align <align.env>] [--workdir <dir>]
#                             [--repo <owner/repo>] [--pr <N>] [--base <ref>]
#                             [--focus <text>] [--fresh]
#
# --align consumes the file written by align-to-pr.sh and inherits the checkout,
# the PR number, the upstream repo and the PR base sha from it.
#
# Everything is written under <ctx>. Nothing inside the git worktree is touched.
set -euo pipefail

CTX=""
ALIGN_FILE=""
WORKDIR=""
UPSTREAM_REPO=""
PR_NUMBER=""
BASE_REF=""
FOCUS=""
FRESH=0

while [ $# -gt 0 ]; do
    case "$1" in
        --ctx)     CTX="$2"; shift 2 ;;
        --align)   ALIGN_FILE="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --repo)    UPSTREAM_REPO="$2"; shift 2 ;;
        --pr)      PR_NUMBER="$2"; shift 2 ;;
        --base)    BASE_REF="$2"; shift 2 ;;
        --focus)   FOCUS="$2"; shift 2 ;;
        --fresh)   FRESH=1; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# ------------------------------------------------------- inherit from align-to-pr
ALIGN_MODE=""
DOCS_ROOT=""
ALIGN_BASE_SHA=""
ALIGN_HEAD_SHA=""
if [ -n "$ALIGN_FILE" ]; then
    [ -f "$ALIGN_FILE" ] || { echo "ERROR: --align file not found: $ALIGN_FILE" >&2; exit 2; }
    read_align() { sed -n "s/^$1=//p" "$ALIGN_FILE" | head -n 1; }
    [ -n "$WORKDIR" ]       || WORKDIR="$(read_align WORKDIR)"
    [ -n "$PR_NUMBER" ]     || PR_NUMBER="$(read_align PR_NUMBER)"
    [ -n "$UPSTREAM_REPO" ] || UPSTREAM_REPO="$(read_align UPSTREAM_REPO)"
    [ -n "$BASE_REF" ]      || BASE_REF="$(read_align PR_BASE_REF)"
    ALIGN_MODE="$(read_align ALIGN_MODE)"
    DOCS_ROOT="$(read_align DOCS_ROOT)"
    ALIGN_BASE_SHA="$(read_align PR_BASE_SHA)"
    ALIGN_HEAD_SHA="$(read_align PR_HEAD_SHA)"
fi

if [ -n "$WORKDIR" ]; then
    cd "$WORKDIR"
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ -n "$ALIGN_HEAD_SHA" ] && [ "$(git rev-parse HEAD)" != "$ALIGN_HEAD_SHA" ]; then
    echo "ERROR: $REPO_ROOT is not at the aligned PR head $ALIGN_HEAD_SHA." >&2
    echo "       re-run align-to-pr.sh before preparing the context." >&2
    exit 1
fi

if [ "$(git rev-parse --is-shallow-repository)" != "false" ]; then
    echo "ERROR: shallow repository; an authoritative three-dot diff needs full history." >&2
    echo "       run: git fetch --unshallow" >&2
    exit 1
fi

HEAD_SHA="$(git rev-parse HEAD)"
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ -z "$BRANCH" ]; then
    BRANCH="(detached at ${HEAD_SHA:0:12})"
    SLUG_SOURCE="${PR_NUMBER:+pr-$PR_NUMBER}"
    [ -n "$SLUG_SOURCE" ] || SLUG_SOURCE="detached"
else
    SLUG_SOURCE="$BRANCH"
fi
BRANCH_SLUG="$(printf '%s' "$SLUG_SOURCE" | tr -c 'A-Za-z0-9._-' '-')"

# ---------------------------------------------------------------- context dir
if [ -z "$CTX" ]; then
    CTX="${TMPDIR:-/tmp}/doris-repo-review/${BRANCH_SLUG}-${HEAD_SHA:0:12}"
fi
if [ "$FRESH" = "1" ] && [ -d "$CTX" ]; then
    rm -rf "$CTX"
fi
mkdir -p "$CTX/ledger"
CTX="$(cd "$CTX" && pwd)"

# ------------------------------------------------------------- resolve the PR
if [ -z "$UPSTREAM_REPO" ]; then
    UPSTREAM_REPO="apache/doris"
fi

PR_TITLE=""
PR_URL=""
PR_STATE=""
PR_BASE_SHA=""
if command -v gh >/dev/null 2>&1; then
    # A detached checkout has no branch to look a PR up by; --pr / --align supplies it.
    if [ -z "$PR_NUMBER" ] && [ -n "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" ]; then
        PR_NUMBER="$(gh pr list -R "$UPSTREAM_REPO" --head "$BRANCH" --state all \
            --json number,state --jq 'sort_by(.state == "OPEN" | not) | .[0].number // empty' 2>/dev/null || true)"
    fi
    if [ -n "$PR_NUMBER" ]; then
        if PR_JSON="$(gh api "repos/${UPSTREAM_REPO}/pulls/${PR_NUMBER}" 2>/dev/null)"; then
            printf '%s' "$PR_JSON" > "$CTX/pr.json"
            PR_TITLE="$(jq -r '.title // ""'    <<<"$PR_JSON")"
            PR_URL="$(jq -r   '.html_url // ""' <<<"$PR_JSON")"
            PR_STATE="$(jq -r '.state // ""'    <<<"$PR_JSON")"
            PR_BASE_SHA="$(jq -r '.base.sha // ""' <<<"$PR_JSON")"
            [ -n "$BASE_REF" ] || BASE_REF="$(jq -r '.base.ref // ""' <<<"$PR_JSON")"
        else
            PR_NUMBER=""
        fi
    fi
fi
[ -n "$PR_BASE_SHA" ] || PR_BASE_SHA="$ALIGN_BASE_SHA"
[ -n "$BASE_REF" ] || BASE_REF="master"

# --------------------------------------------------------- resolve the base commit
# Prefer the PR's real base sha (exactly what CI diffs against). Fall back to a
# local ref tip when that commit is not present in this clone.
BASE_SHA=""
BASE_SOURCE=""
if [ -n "$PR_BASE_SHA" ] && git cat-file -e "${PR_BASE_SHA}^{commit}" 2>/dev/null; then
    BASE_SHA="$PR_BASE_SHA"
    BASE_SOURCE="PR base sha (matches CI)"
else
    for cand in "upstream/$BASE_REF" "origin/$BASE_REF" "$BASE_REF"; do
        if resolved="$(git rev-parse -q --verify "${cand}^{commit}" 2>/dev/null)"; then
            BASE_SHA="$resolved"
            BASE_SOURCE="local ref ${cand}"
            break
        fi
    done
fi
if [ -z "$BASE_SHA" ]; then
    echo "ERROR: cannot resolve a base commit for '$BASE_REF'." >&2
    echo "       pass --base <ref>, or fetch the base branch first." >&2
    exit 1
fi

MERGE_BASE="$(git merge-base "$BASE_SHA" "$HEAD_SHA")"
DIFF_RANGE="${BASE_SHA}...${HEAD_SHA}"

# ------------------------------------------------------------------ worktree state
git status --porcelain > "$CTX/worktree_status.txt"
DIRTY_COUNT="$(grep -c . "$CTX/worktree_status.txt" || true)"

# ------------------------------------------------------------------ the diff itself
# A large move-heavy PR blows past the default rename limit and git degrades to a
# noisy warning plus add/delete pairs, so raise it once for every diff below.
GIT_DIFF=(git -c diff.renameLimit=32768 diff --no-ext-diff --no-color)

"${GIT_DIFF[@]}" "$DIFF_RANGE"                                  > "$CTX/pr.diff"
"${GIT_DIFF[@]}" --name-only "$DIFF_RANGE"                      > "$CTX/pr_changed_files.txt"
# One row per changed file, for the mechanical coverage report of step 6a.
# A file nobody read is not a file with no findings.
{
    printf 'path\tstatus\n'
    "${GIT_DIFF[@]}" --name-status "$DIFF_RANGE" | awk -F'\t' 'NF>=2 {print $NF "\t" $1}'
} > "$CTX/coverage_checklist.tsv"
"${GIT_DIFF[@]}" --name-status -M "$DIFF_RANGE"                 > "$CTX/pr_changed_files_status.txt"
"${GIT_DIFF[@]}" --stat "$DIFF_RANGE"                           > "$CTX/pr_diffstat.txt"
git log --oneline --no-decorate "${MERGE_BASE}..${HEAD_SHA}"    > "$CTX/pr_commits.txt"

# --------------------------------------------- new-side line ranges (anchor source)
"${GIT_DIFF[@]}" -U0 "$DIFF_RANGE" > "$CTX/pr.u0.diff"
python3 - "$CTX/pr.u0.diff" "$CTX/changed_line_ranges.txt" "$CTX/changed_line_ranges.tsv" <<'PY'
import re
import sys
from collections import OrderedDict

u0_path, human_path, tsv_path = sys.argv[1], sys.argv[2], sys.argv[3]

hunk_re = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
files = OrderedDict()
new_path = None
old_path = None

for line in open(u0_path, encoding="utf-8", errors="replace"):
    if line.startswith("--- "):
        old_path = line[4:].strip()
        continue
    if line.startswith("+++ "):
        raw = line[4:].strip()
        new_path = None if raw == "/dev/null" else raw[2:] if raw.startswith("b/") else raw
        key = new_path or (None if old_path in (None, "/dev/null")
                           else (old_path[2:] if old_path.startswith("a/") else old_path))
        if key:
            files.setdefault(key, {"added": [], "removed": [], "deleted_file": new_path is None})
        continue
    m = hunk_re.match(line)
    if not m or new_path is None and old_path in (None, "/dev/null"):
        continue
    key = new_path or (old_path[2:] if old_path.startswith("a/") else old_path)
    entry = files.setdefault(key, {"added": [], "removed": [], "deleted_file": new_path is None})
    old_start, old_len = int(m.group(1)), int(m.group(2) or 1)
    new_start, new_len = int(m.group(3)), int(m.group(4) or 1)
    if new_len > 0:
        entry["added"].append((new_start, new_start + new_len - 1))
    if old_len > 0 and new_len == 0:
        # pure deletion: nothing exists on the new side, anchor to the seam
        entry["removed"].append((max(new_start, 1), old_len))

def fmt(ranges):
    return ", ".join(f"{a}" if a == b else f"{a}-{b}" for a, b in ranges) or "(none)"

with open(human_path, "w", encoding="utf-8") as human, open(tsv_path, "w", encoding="utf-8") as tsv:
    human.write("# New-side (post-change) line ranges touched by this diff.\n")
    human.write("# Cite findings as `path:line` / `path:start-end` using THESE numbers.\n\n")
    for path, entry in files.items():
        if entry["deleted_file"]:
            human.write(f"## {path}  [FILE DELETED]\n\n")
            continue
        human.write(f"## {path}\n")
        human.write(f"  added/modified lines : {fmt(entry['added'])}\n")
        if entry["removed"]:
            seams = ", ".join(f"after line {a} (-{n})" for a, n in entry["removed"])
            human.write(f"  pure deletions       : {seams}\n")
        human.write("\n")
        for a, b in entry["added"]:
            tsv.write(f"{path}\t{a}\t{b}\n")
PY
rm -f "$CTX/pr.u0.diff"

# ---------------------------------------------------- required AGENTS.md guides
python3 - "$REPO_ROOT" "$CTX/pr_changed_files.txt" "$CTX/required_agents.txt" "$CTX/required_agents_prompt.txt" <<'PY'
import sys
from pathlib import Path, PurePosixPath

repo_root = Path(sys.argv[1]).resolve()
changed = Path(sys.argv[2])
out_list = Path(sys.argv[3])
out_block = Path(sys.argv[4])

agents, seen = [], set()

def add(rel: PurePosixPath) -> None:
    text = rel.as_posix()
    if text in seen:
        return
    if (repo_root / text).is_file():
        agents.append(text)
        seen.add(text)

add(PurePosixPath("AGENTS.md"))
for line in changed.read_text(encoding="utf-8", errors="replace").splitlines():
    value = line.strip()
    if not value:
        continue
    parts = PurePosixPath(value).parts
    for index in range(1, len(parts)):
        add(PurePosixPath(*parts[:index]) / "AGENTS.md")

out_list.write_text("".join(f"{a}\n" for a in agents), encoding="utf-8")
out_block.write_text("".join(f"- {a}\n" for a in agents) or "- (none)\n", encoding="utf-8")
PY

# ------------------------------------------------- existing PR review threads
if [ -n "$PR_NUMBER" ] && command -v gh >/dev/null 2>&1; then
    MAX_THREADS=30
    MAX_BODY_CHARS=1200
    if gh api --paginate --slurp "repos/${UPSTREAM_REPO}/pulls/${PR_NUMBER}/comments" \
            > "$CTX/pr_review_comments_pages.json" 2>"$CTX/pr_review_comments_error.log" \
        && jq 'add | sort_by((.in_reply_to_id // .id), .id)' "$CTX/pr_review_comments_pages.json" \
            > "$CTX/pr_review_comments.json" 2>>"$CTX/pr_review_comments_error.log" \
        && jq -r '
            def shorten($limit):
              if (. // "" | length) > $limit then .[0:$limit] + "...(truncated)" else . // "" end;
            if length == 0 then
              "No existing inline review comments or replies were found for this PR."
            else
              group_by(.in_reply_to_id // .id)
              | sort_by(.[0].created_at // "") | reverse | .[:$max_threads]
              | map(
                  . as $thread | $thread[0] as $root
                  | "### " + ($root.path // "(unknown path)") + ":" + (($root.line // $root.original_line // "n/a") | tostring)
                  + "\nURL: " + ($root.html_url // "")
                  + "\nComments:\n"
                  + ($thread | map(
                        "- " + (.user.login // "unknown") + " at " + (.created_at // "")
                        + (if .in_reply_to_id then " (reply):" else " (original comment):" end) + "\n"
                        + ((.body | shorten($max_body_chars)) | split("\n") | map("    " + .) | join("\n"))
                    ) | join("\n"))
              ) | join("\n\n")
            end
          ' --argjson max_threads "$MAX_THREADS" --argjson max_body_chars "$MAX_BODY_CHARS" \
            "$CTX/pr_review_comments.json" > "$CTX/pr_review_threads.md" 2>>"$CTX/pr_review_comments_error.log"; then
        :
    else
        printf '%s\n' \
            'Existing PR review threads could not be fetched for this run.' \
            'Proceed with the review without this auxiliary context.' > "$CTX/pr_review_threads.md"
    fi
    rm -f "$CTX/pr_review_comments_pages.json"
else
    printf '%s\n' 'No PR is associated with this branch; there is no existing inline review context.' \
        > "$CTX/pr_review_threads.md"
fi

# ------------------------------------------------------------------ user focus
if [ -n "$(printf '%s' "$FOCUS" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$FOCUS" > "$CTX/review_focus.txt"
elif [ ! -f "$CTX/review_focus.txt" ]; then
    printf 'No additional user-provided review focus.\n' > "$CTX/review_focus.txt"
fi

# ---------------------------------------------------------------- ledger seed
if [ ! -f "$CTX/ledger/README.md" ]; then
    cat > "$CTX/ledger/README.md" <<'LEDGER'
# Shared Subagent Review Ledger

Shared source of truth for the subagent-assisted review. One file per owner so
that concurrent subagents never patch the same file.

| File | Owner | Purpose |
|---|---|---|
| `00-main-risk-scan.md`   | main agent | initial risk scan, written BEFORE any subagent is spawned |
| `sub-<round>-<slug>.md`  | one subagent | that subagent's candidate findings, append-only |
| `main-merged.md`         | main agent | merged / verified / dismissed candidates, final comment set |

Rules:
- Every subagent MUST read every file in this directory before reviewing.
- A subagent writes ONLY its own `sub-*.md` file. It must not touch another
  subagent's file, `00-main-risk-scan.md`, `main-merged.md`, repository source
  files, or GitHub.
- Avoid duplicates. If a candidate overlaps an existing one, record it in your
  own file with a duplicate note referencing the existing candidate ID.
- The main agent owns final status, deduplication, and the review documents.

Candidate statuses: `proposed_by_subagent`, `accepted`, `dismissed_with_evidence`, `duplicated`.

Candidate format:

- ID:
  Owner:
  Status:
  Path:
  Line:          <new-side line or start-end, must match changed_line_ranges.txt or be justified>
  Severity:      Blocker | Major | Minor | Nit
  Claim:
  Evidence:      <call chain / concrete trigger scenario / file:line citations>
  Duplicate relationship:
  Recommendation:
LEDGER
fi

if [ ! -f "$CTX/ledger/00-main-risk-scan.md" ]; then
    cat > "$CTX/ledger/00-main-risk-scan.md" <<'SCAN'
# Main Initial Risk Scan

Written by the MAIN agent before any subagent is spawned. One entry per risk focus.

- ID:
  Status:                                  <open | assigned | resolved>
  Changed files/lines:
  Related mechanisms to inspect:
  Why suspicious:
  Required upstream/downstream files or paths:
  Question for risk-focused subagent:
  Final conclusion:
SCAN
fi

if [ ! -f "$CTX/ledger/main-merged.md" ]; then
    cat > "$CTX/ledger/main-merged.md" <<'MERGED'
# Main Merged Findings

Owned by the main agent.

## Merged Findings

- ID:
  Source IDs:
  Status:                                  <accepted | dismissed_with_evidence | duplicated>
  Severity:
  Path:
  Line:
  Claim:
  Evidence:
  Main verification:
  Proposed finding body:

## Dismissed Or Duplicate Points

## Convergence Rounds

| Round | Subagents | New candidates | Verdict |
|---|---|---|---|
MERGED
fi

# ------------------------------------------------------------------ meta + report
[ -n "$DOCS_ROOT" ] || DOCS_ROOT="$REPO_ROOT"
# --------------------------------------------------- prior runs of this same PR
# A PR is normally reviewed more than once. Each run used to start from zero and
# leave nothing behind, so the expensive half of a review - the dismissals, with
# their evidence - was re-derived every time, and "was this considered last
# time?" was unanswerable. Runs are kept under a stable per-PR directory that is
# outside both the session scratchpad and the git worktree.
STATE_ROOT="${DORIS_REVIEW_STATE:-${XDG_CACHE_HOME:-$HOME/.cache}/doris-repo-review}"
STATE_DIR=""
PRIOR_RUNS=0
if [ -n "${PR_NUMBER:-}" ]; then
    STATE_DIR="${STATE_ROOT}/$(printf '%s' "${UPSTREAM_REPO}" | tr '/' '-')/pr-${PR_NUMBER}"
    mkdir -p "$STATE_DIR/runs"
    mkdir -p "$CTX/prior_runs"
    for run in "$STATE_DIR"/runs/*/; do
        [ -d "$run" ] || continue
        head7="$(basename "$run")"
        # The run for this very head is this run, not a prior one.
        [ "$head7" = "${HEAD_SHA:0:7}" ] && continue
        [ -f "$run/main-merged.md" ] || continue
        cp "$run/main-merged.md" "$CTX/prior_runs/${head7}-main-merged.md"
        [ -f "$run/meta.env" ] && cp "$run/meta.env" "$CTX/prior_runs/${head7}-meta.env"
        PRIOR_RUNS=$((PRIOR_RUNS + 1))
    done
    [ -f "$STATE_DIR/index.tsv" ] && cp "$STATE_DIR/index.tsv" "$CTX/prior_runs/index.tsv"
fi

{
    echo "REPO_ROOT=$REPO_ROOT"
    echo "DOCS_ROOT=$DOCS_ROOT"
    echo "ALIGN_MODE=${ALIGN_MODE:-none}"
    echo "CTX=$CTX"
    echo "UPSTREAM_REPO=$UPSTREAM_REPO"
    echo "BRANCH=$BRANCH"
    echo "PR_NUMBER=${PR_NUMBER:-}"
    echo "PR_TITLE=${PR_TITLE:-}"
    echo "PR_URL=${PR_URL:-}"
    echo "PR_STATE=${PR_STATE:-}"
    echo "BASE_REF=$BASE_REF"
    echo "BASE_SHA=$BASE_SHA"
    echo "BASE_SOURCE=$BASE_SOURCE"
    echo "HEAD_SHA=$HEAD_SHA"
    echo "MERGE_BASE=$MERGE_BASE"
    echo "DIFF_RANGE=$DIFF_RANGE"
    echo "DIRTY_FILES=$DIRTY_COUNT"
    echo "STATE_DIR=${STATE_DIR:-}"
    echo "PRIOR_RUNS=${PRIOR_RUNS:-0}"
    echo "REVIEW_DATE=$(date +%Y-%m-%d)"
} > "$CTX/meta.env"

echo "=== doris-repo-review context ready ==="
cat "$CTX/meta.env"
echo
echo "changed files : $(grep -c . "$CTX/pr_changed_files.txt" || true)"
echo "commits       : $(grep -c . "$CTX/pr_commits.txt" || true)"
echo "diff lines    : $(wc -l < "$CTX/pr.diff" | tr -d ' ')"
echo "diffstat      : $(tail -n 1 "$CTX/pr_diffstat.txt")"
echo
if [ "${PRIOR_RUNS:-0}" -gt 0 ]; then
    echo "prior runs of this PR (read them, see SKILL.md 2.1): $PRIOR_RUNS"
    ls -1 "$CTX/prior_runs" | sed 's/^/  /'
    echo
else
    echo "prior runs of this PR: none - this is the first review"
    echo
fi
echo "required AGENTS.md:"
sed 's/^/  /' "$CTX/required_agents.txt"
if [ "${DIRTY_COUNT:-0}" -gt 0 ]; then
    echo
    echo "WARNING: $DIRTY_COUNT uncommitted path(s) in the worktree are NOT part of the reviewed diff:"
    sed 's/^/  /' "$CTX/worktree_status.txt"
fi
