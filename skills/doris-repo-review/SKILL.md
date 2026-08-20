---
name: doris-repo-review
description: Given a PR URL (`/doris-repo-review https://github.com/apache/doris/pull/66807`), first check whether the current directory's branch and commit match that PR, and if they do not, align the current directory to the PR head without disturbing local work (refuse to switch when tracked files are modified and hand the decision back to the user); then review it with the same pipeline apache/doris CI runs (Code Review Runner) - main-agent risk scan, 1-3 full-review subagents plus risk-focused subagents, shared-ledger convergence (at most 3 rounds), and one English plus one Chinese review document written into review-docs/. A local run has no GitHub inline comments, so every finding must carry a path:line anchor and a verbatim snippet, verified by a script. When the review passes (no Blocker and no Major), it also posts one strongly formatted, machine-readable PASS comment on the PR from the local gh account - review date, reviewed commit sha, status, model, and notes for maintainers - after showing the exact body to the user for confirmation. Use when the user says "/doris-repo-review <PR URL>", "review this PR", "review it the way the CI pipeline does", or "review this PR locally like CI". Read-only against the source - no build, no tests, no changes to repository files; the PASS comment is the only GitHub write, and a REQUEST_CHANGES review posts nothing at all.
---

# Local pipeline-style Doris code review

This skill reviews a Pull Request against a **local clone of the Apache Doris source repository**.
It is a contributor-side workflow, not a cluster-operations skill: it never talks to a running
cluster and never needs one.

Usage:

```
/doris-repo-review https://github.com/apache/doris/pull/66807
/doris-repo-review https://github.com/apache/doris/pull/66807 focus on class loading and compatibility
/doris-repo-review 66807            # a bare number defaults to apache/doris
```

This ports the review flow of `apache/doris/.github/workflows/code-review-runner.yml` to a local
machine: **first align the current directory to the PR head**, take the diff from local git, and
produce one English and one Chinese document under the current directory's `review-docs/`.
Everything else - required reading, main-agent risk scan, subagent split, shared ledger, at most
3 convergence rounds, an explicit conclusion per checkpoint - matches CI.

**The scope is the one worktree you are standing in.** No other worktree is scanned, chosen, or
created; no environment variable selects a different directory; nothing is assumed about the
machine's directory layout.

Let `$S` be this skill's own `scripts/` directory (with a default Claude Code install that is
`~/.claude/skills/doris-repo-review/scripts`):

```bash
$S/align-to-pr.sh <PR> --check                      # diagnosis only, changes nothing
$S/align-to-pr.sh <PR> --out "$CTX/align.env"       # step 1: align the current directory
$S/prepare-review-context.sh --ctx "$CTX" --align "$CTX/align.env"   # step 2: gather context
$S/coverage-report.sh --ctx "$CTX"                  # step 6a: what has nobody read yet
python3 $S/verify-anchors.py --ctx "$CTX" --doc <en> --doc <zh>      # step 9: verify anchors
$S/post-pass-comment.sh --ctx "$CTX" --model <id> ... --dry-run      # step 10: PASS comment
$S/save-run-state.sh --ctx "$CTX" --verdict ... --findings b,m,mi,n  # step 11: leave state for next time
```

| File | Purpose |
|---|---|
| `scripts/align-to-pr.sh` | Resolve the PR, diagnose how the current directory relates to it, align it to the PR head |
| `scripts/prepare-review-context.sh` | Produce the authoritative diff, new-side line ranges, required AGENTS.md list, existing comments, ledger skeleton |
| `scripts/coverage-report.sh` | Mechanical check of which changed files no ledger file has mentioned yet |
| `scripts/verify-anchors.py` | Check that every `path:line` anchor really exists and that both documents expose the same finding IDs |
| `scripts/post-pass-comment.sh` | Render and post the machine-readable PASS comment; refuses everything that is not a pass |
| `scripts/save-run-state.sh` | Persist this run's merged ledger under the stable per-PR state directory, so the next review inherits its dismissals |
| `references/prompts.md` | Subagent prompt templates (CI wording, carried over verbatim) |
| `references/doc-templates.md` | Templates for both documents, anchor format, verdict rule |
| `references/pr-comment-format.md` | The `doris-repo-review/v1` comment schema, field meanings, and how a program reads it back |

Requirements: `git`, an authenticated `gh` CLI, `jq`, and `python3`. The clone must have full
history (`git fetch --unshallow` on a shallow one), because the authoritative diff is a three-dot
diff from the merge base.

---

## 0. Ground rules

1. **Touch only the current directory, and never disturb local work.** When the current directory
   has **modified tracked files**, refuse to switch, report the situation, and let the user commit
   or stash it themselves - **never stash, reset, or delete a branch on the user's behalf**, and
   never go hunting for some other directory to work in. Every switch is
   `git checkout --detach`, so branch refs stay exactly where they were.
2. **Read-only review.** Do not build, do not run tests, do not modify any source file in the
   repository. The only local writes allowed are the two documents under `review-docs/` and the
   context directory `$CTX`.
   **Exactly one thing may ever be written to GitHub**: the PASS comment of step 10, only when the
   verdict is APPROVE, only through `post-pass-comment.sh`, and only after the user has seen the
   rendered body and said go. A REQUEST_CHANGES review posts nothing. No inline comments, no
   review submission, no labels, no edits to the PR body - and never a comment on any PR other
   than the one being reviewed.
3. **The diff has exactly one source**: `$CTX/pr.diff` and `$CTX/pr_changed_files.txt`. Do not
   reach for `gh pr diff`, the web UI, or a hand-rolled `git diff` to get the change list - a
   different way of fetching it means a different base.
4. **Confirm a path before reading it.** If a path is not already confirmed by
   `pr_changed_files.txt`, `pr.diff`, or the output of an earlier successful command, run
   `rg --files` to confirm it first.
4a. **Evidence may live outside the repository, and you are expected to go and get it.** Rule 3
   fixes where the *change list* comes from; it says nothing about where *evidence* comes from.
   When a dependency's own content is what decides the behaviour under review, read that
   dependency: unzip the jar in `~/.m2/repository/...` that the build actually pins and read the
   resource inside it, read the `-sources.jar` of the library whose semantics the change relies on,
   read the vendored service definition, read the JDK class whose contract a comment claims.
   A review that never leaves the diff cannot find a defect whose two halves are "the changed line"
   and "what the changed line now reaches" - which is exactly where the worst findings live.
   Always name the artifact and its version in the finding, so the evidence is reproducible.
5. **Do not stop at the first blocking issue.** Work through the changed files, the related
   control flow, the tests, and the parallel or special-case paths.
6. **Every suspicion must reach a conclusion**: it becomes a finding, is excluded as "already
   covered by an existing comment", or is ruled out with concrete code evidence and written into
   "Considered and Dismissed". Silently dropping a suspicion means the review is not finished.
7. **There are no inline comments locally**, so an anchor is the reader's only way in. Every
   finding must carry a `path:line` anchor (new-side line numbers) plus a verbatim snippet, and
   the documents must pass `verify-anchors.py` at the end.

---

## 1. Align the current directory

```bash
CTX="<session scratchpad>/review-ctx"
$S/align-to-pr.sh <PR> --out "$CTX/align.env"
```

The script does four things, **all of them against the current worktree only**:

1. **Resolve the PR**: a URL, `owner/repo#N`, or a bare number are all accepted; `gh api` supplies
   title, state, head ref/repo/sha, and base ref/sha.
2. **Diagnose consistency** (the two checks the user explicitly wants):
   - `branch check`: is the current branch the PR's head branch?
   - `commit check`: `same` / `ahead:N` / `behind:N` / `diverged:a/b` / `unrelated`
   **Relay both lines to the user verbatim.** In particular `ahead:N` means there are local commits
   that were never pushed, and **they are not part of the review**.
3. **Fetch the PR head**: `git fetch <upstream> +refs/pull/N/head:refs/doris-review/pr-N`. It goes
   through `refs/pull/*`, so a fork PR needs no extra remote. The fetched sha must equal the head
   sha from the API; if it does not, the PR was pushed to while the context was being prepared -
   the script re-reads the API once and errors out asking for a re-run if it still differs (this
   mirrors CI's "PR changed while review context was being prepared" guard).
4. **Align the current directory**:

   | State of the current directory | Action |
   |---|---|
   | HEAD already equals the PR head | `ALIGN_MODE=already`, nothing to do |
   | Clean | `git checkout --detach <PR head>`, `ALIGN_MODE=switched` |
   | Modified tracked files / a rebase, merge, or cherry-pick in progress | `ALIGN_MODE=blocked`, **refuse and exit** |

   "Clean" means **no modified tracked files**. Untracked files do not count (`git checkout` never
   deletes them, and refuses outright when it would overwrite one), so an untracked directory such
   as `review-docs/` does not affect the verdict and survives the switch.

**What to do when BLOCKED**: relay the dirty-file list the script printed, then ask the user to
pick - (a) commit it themselves, (b) stash it themselves, or (c) start over in a different
directory. **Do not perform any of those for them**; once they have chosen and acted, re-run this
skill. To see the diagnosis without changing anything, use `--check` (it still prints the full
branch check / commit check before reporting BLOCKED).

Once aligned, `$CTX/align.env` supplies `WORKDIR` (= the current directory), `DOCS_ROOT`
(= `WORKDIR`), `PR_HEAD_SHA` / `PR_BASE_SHA`, `PREV_REF` (the restore point),
`BRANCH_MATCHES_PR`, and `LOCAL_VS_PR`.

---

## 2. Prepare the context

```bash
$S/prepare-review-context.sh \
    --ctx "$CTX" --align "$CTX/align.env" [--focus "<user focus>"] [--fresh]
```

`--align` carries over `WORKDIR`, the PR number, the upstream repo, and the PR base sha, and
verifies the checkout really is parked on the PR head (if it is not, the script errors out and
asks you to redo step 1). `--fresh` wipes and rebuilds everything including the ledger; without it
the ledger is preserved so a multi-round run can continue. Whatever free text the user typed after
the PR URL on the command line is the `--focus` value.

Output (under `$CTX`):

| File | Contents |
|---|---|
| `meta.env` | PR info, base/head sha, diff range, `DOCS_ROOT`, `ALIGN_MODE`, date, dirty-file count |
| `pr.diff` / `pr_changed_files.txt` / `pr_changed_files_status.txt` | The authoritative diff and change list |
| `changed_line_ranges.txt` / `.tsv` | **New-side (post-change) line ranges** - the source for anchors |
| `pr_commits.txt` / `pr_diffstat.txt` | Commit list and change size |
| `pr_review_threads.md` | Existing inline comments (at most 30 threads, each body truncated at 1200 chars) |
| `required_agents.txt` / `required_agents_prompt.txt` | Required AGENTS.md files, derived from the changed files' ancestor directories |
| `review_focus.txt` | The user's focus points |
| `worktree_status.txt` | Uncommitted changes in the review tree (**out of review scope**; call them out in the documents) |
| `ledger/` | Shared-ledger skeleton |
| `coverage_checklist.tsv` | One row per changed file, for the mechanical coverage report of step 6a |
| `prior_runs/` | What earlier reviews of **this same PR** concluded - see below |

If `BASE_SOURCE` is not `PR base sha (matches CI)`, the baseline differs from CI's and the
documents must say so.

### 2.1 Prior runs of the same PR are input, not history

A PR is usually reviewed more than once - the author pushes, you re-run. Each run used to start
from zero, re-deriving the same dismissals and re-reading the same files, and none of it survived.
That is the single largest source of wasted budget, and it is why "why did the last review not
find this?" used to be unanswerable.

`prepare-review-context.sh` therefore keeps every run's merged ledger under a **stable per-PR
state directory**, outside the session scratchpad and outside the repository:

```
${DORIS_REVIEW_STATE:-${XDG_CACHE_HOME:-$HOME/.cache}/doris-repo-review}/<owner>-<repo>/pr-<N>/
    runs/<head7>/main-merged.md      one per reviewed head
    runs/<head7>/meta.env
    index.tsv                        head sha, date, verdict, finding counts
```

and copies whatever it finds into `$CTX/prior_runs/`. **Read it as part of step 3**, right after
`pr_review_threads.md`, and treat it exactly the way you treat an existing review thread:

- Its **"Considered and Dismissed" table is the expensive part.** A dismissal that still holds does
  not need re-deriving; carry it forward into this run's table with its original evidence and a
  note that it was re-confirmed (or say why it no longer holds). Only re-derive a dismissal whose
  premise the new head could have changed.
- Its accepted findings tell you what the author has already been told. One that is now fixed is
  worth one line in the closing report ("fixed at this head"), not a finding.
- **If a prior run reviewed a different head, say so and check what moved.** The branch may have
  been rebased, so comparing by commit hash is unsafe: compare content
  (`git show <old head>:<path>`) before claiming a finding is new.

An empty `prior_runs/` means this is the first review of this PR - not that nothing was ever
reviewed. Say which it is in "Coverage and Limits".

---

## 3. Required reading (in this order)

Before looking at any code, the main agent reads, in order:

1. `$WORKDIR/.claude/skills/code-review/SKILL.md` - the Doris review checklist; follow it strictly
   throughout. On an older branch that does not have it, fetch it with
   `gh api repos/apache/doris/contents/.claude/skills/code-review/SKILL.md?ref=master`.
2. **Every** AGENTS.md listed in `$CTX/required_agents.txt`, each one read in full. Listing the
   directory or grepping the path does not count.
3. `$CTX/pr_review_threads.md` - treat every existing comment as already-known context. **Do not
   raise** the same or a substantially similar issue again, even phrased differently. Raise a
   similar concern only when this PR introduces a genuinely different instance somewhere else that
   the existing comments do not cover, and say why it is distinct.
3a. Everything under `$CTX/prior_runs/` - what earlier reviews of this same PR concluded. See
   section 2.1: dismissals carry forward with their evidence, accepted findings that are now fixed
   become one line in the closing report, and a prior run on a different head means comparing
   content rather than commit hashes.
4. `$CTX/review_focus.txt` - do the full review as usual and pay extra attention to these points;
   the final documents must respond to each one, even if the conclusion is "no additional issue
   found for this point".
5. All of `$CTX/pr.diff` plus `$CTX/pr_commits.txt`. When the diff is large (> 5000 lines), read it
   in chunks by directory or module until it is covered, and describe how you read it in "Coverage
   and Limits" - do not pretend you read it all.

---

## 4. Main-agent initial risk scan (before spawning any subagent)

**This must be finished before any subagent is spawned.** Read the whole change, understand every
mechanism it touches, then answer: if this PR is wrong, where is it most likely to be wrong? Which
points look risky to you?

Write the result into `$CTX/ledger/00-main-risk-scan.md`, each entry carrying: an ID, the changed
files/lines involved, the related mechanism to inspect, why it is suspicious, the upstream or
downstream files that must be read alongside it, the **specific question** a risk-focused
subagent has to answer, and - see below - a **premise check**.

An empty risk scan means you have not understood the PR yet - go back and read it; do not skip
this step.

### 4.1 Every risk item carries a premise check, and you run it before spawning anything

A risk item always rests on a premise: "this used to be X and is now Y", "nothing validates Z",
"only one caller does W". If the premise is false the subagent spends its entire budget proving
you wrong, and you learn nothing you could not have learned in thirty seconds.

So each entry gets one more field:

```
  Premise:        <the one factual claim the whole item rests on>
  Premise check:  <a single command that confirms or kills it>
  Premise result: <confirmed | FALSE - item dismissed | cannot be checked cheaply>
```

Run every one of them **before** step 5. The check is nearly always a one-liner against the base:

```bash
git show "$BASE_SHA:path/to/File.java" | grep -n 'thing I think is new'
git show "$BASE_SHA:path/to/File.java" | sed -n '120,140p'
rg -n 'symbol' --files-with-matches            # "only one caller" claims
```

A premise that comes back FALSE does not become a subagent - it becomes a row in "Considered and
Dismissed" with the command as its evidence. That row is worth as much as a finding: it is the
part of the review that says "this was checked", and it costs one command instead of one agent.

A premise you genuinely cannot check cheaply is fine - dispatch it, and say in the prompt that the
premise is unverified so the subagent checks it first and stops early if it fails.

---

## 5. Spawn the subagents

Split along the coverage the code-review skill requires, and **send them all in one message so
they run concurrently** (general-purpose subagents):

| Type | Count | Responsibility |
|---|---|---|
| Full-review subagent | 1-3 (depending on PR complexity) | Each owns one slice; **their union must cover the whole PR** and every checkpoint the skill requires |
| Risk-focused subagent | one per suspicious mechanism | Answers exactly one question from the risk scan, independently of the full-review subagents |

Split by **module or mechanism** (for example "FE SPI interface and load path", "Ranger plugin
implementation and class loading", "build scripts and packaging/deployment"), not by dividing the
file count evenly - a split that lands in the middle of a mechanism leaves both halves unable to
see the bug. Give every subagent its own ledger file, `$CTX/ledger/sub-<round>-<id>.md`.

Take the prompts from `references/prompts.md`: section A (shared preamble) plus section B
(full review) or section C (risk-focused), substituting `{CTX}` / `{REPO_ROOT}` (= `$WORKDIR`) /
`{BASE_SHA}` / `{HEAD_SHA}` / `{ROUND}` / `{AGENT_ID}` / `{FOCUS}`. **Every subagent prompt must
state the ledger directory and the path of that subagent's own file.** Section D of that file is a
catalogue of the techniques that actually find things - name the one you want in each prompt
rather than leaving the subagent to invent a method.

> **One implementation difference from CI**: CI uses a single `subagent_review_findings.md` with
> sections; locally, concurrent writes to one file collide on patch, so this becomes **one file per
> owner** under `ledger/`. The semantics are unchanged - a single shared source of truth, everyone
> reads all of it, each writes only their own, the main agent merges.

### 5.1 Round 1 goes out in two waves, because the ledger is empty when it starts

The deduplication rule ("read every file in `ledger/` before reviewing") cannot work in round 1:
every subagent starts at the same instant against an empty directory. In practice three agents
independently rediscover the same defect and three budgets buy one finding.

So round 1 - and only round 1 - is dispatched in two waves:

- **Wave A: the full-review subagents.** All of them concurrently, as before. They own the slices,
  so their coverage is what the union has to span.
- **Wave B: the risk-focused subagents.** Dispatched once wave A returns, concurrently among
  themselves. They read wave A's ledger files first, so a mechanism wave A already settled becomes
  a duplicate note instead of a second investigation, and a risk item wave A has already answered
  is dropped before it costs anything.

Two things make this cheap rather than slow. Wave A is the long pole either way. And the main
agent is not idle in between - it merges wave A (step 6) while wave B runs.

Where two waves genuinely will not fit - a small PR, or a risk item so specific that no
full-review slice touches it - dispatch everything at once and **pre-seed the ledger instead**:
before spawning, write into `00-main-risk-scan.md` the defects you already expect each slice to
surface, so a concurrent agent can recognise one of yours and mark it duplicate rather than
writing it up from scratch.

From round 2 onward the ledger is populated, so all subagents of a round go out together.

---

## 6. Main agent merges, verifies, deduplicates

**Re-read the entire `ledger/` directory every time a subagent returns**, then process each
candidate into `$CTX/ledger/main-merged.md`:

- **Verify**: read the code yourself to confirm it; do not take a subagent's conclusion at face
  value. The common failure modes are treating a local pattern that an upstream guarantee already
  covers as a bug, and an "if A then B" whose A has no concrete scenario.
- **Deduplicate**: against the existing candidates and against the existing comments in
  `pr_review_threads.md`.
- **Assign a status**: `accepted` / `dismissed_with_evidence` / `duplicated`. A dismissal must come
  with concrete code evidence, which goes verbatim into the document's "Considered and Dismissed".
- **Fill the risk items back in**: update `Status` and `Final conclusion` for every entry in
  `00-main-risk-scan.md`.

When this step ends, **no candidate may be left without a status**.

### 6a. Run the coverage report at the end of every round

```bash
$S/coverage-report.sh --ctx "$CTX"
```

It is mechanical, not a judgement: it walks `pr_changed_files.txt` and reports which changed files
no ledger file has so much as mentioned. Finding "13 changed files nobody opened" is a job for
`grep`, not for a subagent in round 3 - and knowing it after round 1 is what lets round 2 be
aimed instead of guessed.

Its output is an input to the next round's slicing, and to the verdict: **a file nobody read is
not a file with no findings.** Either cover it in the next round or read it yourself in step 8.

---

## 7. Convergence loop (at most 3 rounds)

One round = step 5 + step 6 + step 6a. Record the outcome in the `Convergence Rounds` table of
`main-merged.md`, one row per round with: subagents, new candidates **by severity**, coverage gaps
remaining, verdict.

**Convergence is about the verdict, not about the count.** The rounds exist to make you confident
in the answer you are about to give - which findings block the merge - not to empty the well of
Nits. A large PR will yield another Minor for as long as you keep looking, and a rule that waits
for that to stop combined with the re-slicing rule below can never terminate.

So a round **converges** when both hold:

- it produced **no new `Blocker` and no new `Major`**, and
- the step-6a coverage report is clean - every changed file has been read by somebody.

Then go to step 8, and record in the documents that the verdict has been stable since round N.

Otherwise start another round: **re-slice the coverage** based on what this round taught you (do
not re-dispatch the same split unchanged), and add risk-focused subagents for any newly suspicious
mechanism. Aim the new round at where severity actually came from, not at what is left over.

- **Cap of 3 rounds.** If the cap is reached while `Blocker`/`Major` candidates are still
  appearing, or while coverage gaps remain, finish normally but state in the verdict and in
  "Coverage and Limits" that **this review did not converge**, and say which of the two conditions
  failed.
- If the cap is reached with only `Minor`/`Nit` still trickling in, that is **converged**, and the
  documents should say so plainly: "the verdict was settled at round N; later rounds added only
  Minor and Nit findings". Do not report a converged review as a failed one.
- **A round that returns only Nits is a stop signal, not a reason for another round.** Record the
  yield (agents spent, findings by severity) so the next person can see where the returns fell off.

---

## 8. Final sweep

Before writing the documents, walk explicitly through the changed-file list and the open-candidate
list:

- Run `$S/coverage-report.sh --ctx "$CTX"` one last time. Was every changed file covered by at
  least one subagent? Cover the rest yourself, and say in "Coverage and Limits" which files you
  read only here.
- Does every suspicion have a conclusion?
- Did every dismissal carried forward from `prior_runs/` get re-confirmed or re-opened?
- Does every applicable item in Part 1.3 of the code-review skill have an explicit conclusion?
- Is there anywhere you are still unsure about, or that may not have been investigated deeply
  enough? Investigate it now.

Only after the sweep may you write the documents.

---

## 9. Produce the two documents

Write them into `review-docs/` in the **current directory** (`mkdir -p` it if needed), named by the
head that was actually reviewed:

```
review-docs/pr-<N>-review.<head7>.en.md      e.g. pr-66770-review.3f45815.en.md
review-docs/pr-<N>-review.<head7>.zh.md
review-docs/pr-<N>-review.en.md              symlink -> the newest of the above
review-docs/pr-<N>-review.zh.md              symlink -> the newest of the above
```

**Never overwrite an earlier run's document.** The head sha is in the name precisely so a re-review
cannot destroy what the last one concluded: that record is the only way to answer "was this
considered last time, and dismissed with what evidence?" - and once it is gone, it is gone, because
`review-docs/` is untracked. The two unsuffixed names are convenience symlinks, so anything that
links to them keeps working while the history accumulates behind them.

Point `verify-anchors.py` at the real files, not the symlinks. If a document for this exact head
already exists, you are re-running against an unchanged head: overwrite that one, and only that one.

`references/doc-templates.md` holds the templates, the anchor format, and the verdict rule
(`Blocker`/`Major` → REQUEST_CHANGES; only `Minor`/`Nit` → APPROVE). The essentials:

- The two documents are **equivalent in content**: same finding IDs, same order, same anchors. The
  Chinese one is a real Chinese review, not a word-for-word translation; identifiers, paths, log
  messages, config names, code snippets, and the severity words stay in their original form.
- The document header must state: the PR link and state, the **head sha actually reviewed**, the
  diff range, the review directory (`WORKDIR`), and the `branch check` / `commit check` results
  from step 1.
- Every finding must carry: a severity, a `path:line` anchor, a verbatim snippet, and the four
  parts **what is wrong / why it happens / when it bites / suggested fix**. Give a diff patch when
  the fix is small and self-contained; use prose only for architectural problems.
- The "Critical Checkpoints" table needs a conclusion per row; mark a non-applicable one `n/a` with
  a half-line reason - **never delete the row**.
- "Response to Review Focus" answers each of the user's focus points.
- "Considered and Dismissed" lists every excluded suspicion together with its evidence.
- "Coverage and Limits" states: what was read in depth versus skimmed, how the subagents were
  split, what was not verified locally (builds, tests, anything needing a real cluster), the
  uncommitted changes from `worktree_status.txt` that were excluded, **which earlier runs of this
  PR this one builds on** (heads and dates from `prior_runs/`, or "first review of this PR"), and
  **whether the review converged** in the sense of step 7 - naming the round after which the
  verdict stopped moving, and, if it did not converge, which of the two conditions failed.

When they are written, running the verifier is **mandatory**; if it fails, fix the documents and
re-run until it passes:

```bash
python3 $S/verify-anchors.py --ctx "$CTX" \
    --doc review-docs/pr-<N>-review.en.md \
    --doc review-docs/pr-<N>-review.zh.md
```

It checks that anchor paths exist, that line numbers are inside the file, that every finding has at
least one anchor, and that the EN and ZH finding-ID sets match; it also flags anchors pointing at
unchanged context lines - which is usually where a miscomputed line number shows up.

---

## 10. Post the PASS comment to the PR

**Only when the verdict is APPROVE** (no `Blocker`, no `Major`) and `verify-anchors.py` has
passed. A REQUEST_CHANGES review posts nothing at all - say so in the closing report and stop.

Write the notes, dry-run, get a go, post:

```bash
# At most 5 bullets, each anchored where it can be. Skip the file when there is nothing to say.
cat > "$CTX/pr-comment-notes.md" <<'EOF'
- `fe/fe-core/src/main/java/org/apache/doris/X.java:214` — <what the maintainer should know>
EOF

$S/post-pass-comment.sh --ctx "$CTX" \
    --model "<exact model id of this session>" --effort "${CLAUDE_EFFORT:-unknown}" \
    --findings <blocker>,<major>,<minor>,<nit> \
    --rounds <r> --converged <true|false> \
    --notes-file "$CTX/pr-comment-notes.md" \
    --dry-run
```

- **`--model` is the exact model id of the session doing the review** (`claude-opus-5[1m]`,
  `gpt-5.6-sol`, …), taken from what this session was told about itself - never a guess, never a
  bare family name. `--effort` comes from `$CLAUDE_EFFORT`. The comment is a public, signed
  statement about who reviewed the code; both fields are what make it auditable.
- The dry run runs **every** precondition and prints the exact body. **Show that body to the user
  and wait for a go**, then re-run the identical command **without `--dry-run`**. Never post
  without that confirmation.
- The script refuses to post when: any `Blocker`/`Major` is present; the live PR head no longer
  equals the reviewed commit; the PR is not open (`--allow-closed` overrides); the notes are
  malformed or more than five; `converged: false` came without a note. A refusal is a real signal
  - relay it, do not work around it.
- **The PR head moved** means the author pushed during the review: the review is stale, so re-run
  the whole skill instead of posting.
- An earlier v1 comment from the same account for the **same** commit is edited in place; a new
  commit gets a new comment, so each push leaves exactly one record.
- Findings counts, rounds and `converged` must match the documents written in step 9. The counts
  are of *accepted* findings, not of candidates.
- `references/pr-comment-format.md` holds the schema, the field meanings, and the parser snippet.
  **Never hand-write or hand-edit this comment** - the format is a contract other programs read.

---

## 11. Closing report

Tell the user:

1. The paths of both documents, the verdict (REQUEST_CHANGES / APPROVE), the finding count per
   severity, and whether the rounds converged in the sense of step 7 - "the verdict was settled at
   round N" if they did, and which condition failed if they did not. A run that ended with only
   Minor/Nit still arriving **converged**; do not report it as a failure.
1a. **What this run inherited**, when `prior_runs/` was not empty: which heads were reviewed
   before, how many of their dismissals were carried forward, and which of their accepted findings
   are fixed at this head. If no prior run existed, say that this is the first review of this PR.
2. The `branch check` / `commit check` results - especially `ahead:N` (unpushed commits that were
   not reviewed).
3. **What happened to the PASS comment**: the URL when one was posted or updated, or the reason
   nothing was posted (the verdict was REQUEST_CHANGES, the PR head moved, the user said no).
4. **Where the current directory now stands**: with `ALIGN_MODE=switched` it is detached on the PR
   head, and `git checkout <PREV_REF>` restores it. **Do not switch back automatically** - the user
   may still want to read the code.
5. `review-docs/` **is not gitignored in the doris repository**, so **do not commit it
   automatically**; leave that to the user.
6. **Save the run state before you finish** - this is what makes the next review cheaper and makes
   this one auditable:

   ```bash
   $S/save-run-state.sh --ctx "$CTX" \
       --verdict REQUEST_CHANGES --findings <blocker>,<major>,<minor>,<nit> \
       --rounds <r> --converged <true|false> \
       --docs "review-docs/pr-<N>-review.<head7>.en.md" --note "<one line: the headline finding>"
   ```

   It runs for **both** verdicts - a REQUEST_CHANGES review has just as much to hand forward as a
   pass, and rather more. Tell the user where it was saved and print the per-PR history it echoes,
   so the sequence of reviews of this PR is visible in one place.

---

## 12. Mapping to the CI pipeline

| CI (code-review-runner.yml) | Local |
|---|---|
| `codex exec --goal` (gpt-5.6-sol, xhigh) | The main agent of this session |
| checkout the PR head sha | `align-to-pr.sh` detaches **the current directory** to the same sha |
| `git diff BASE...HEAD` as the authoritative diff | Same, produced by `prepare-review-context.sh` |
| "PR changed while preparing" guard | The fetched sha must equal the API head sha, otherwise a re-run is required |
| `prepare_review_agents.py` collecting AGENTS.md | Same ancestor-directory algorithm, built into the script |
| Fetch existing inline threads (30 threads / 1200 chars) | Same jq |
| Text after `/review` = review focus | Free text after the PR URL → `--focus` |
| Single-file ledger with sections | A `ledger/` directory, one file per owner |
| Main risk scan → 1-3 full-review subagents + risk-focused → merge → ≤3 rounds | Same shape, three local additions: every risk item carries a premise check the main agent runs before dispatch (4.1); round 1 goes out in two waves so the ledger can deduplicate (5.1); a round converges on **severity plus coverage**, not on "no new candidates at all" (7) |
| CI reviews one push in isolation | Earlier runs of the same PR are loaded from a stable state directory and read as input (2.1); documents are named by head sha and never overwritten (9) |
| `gh pr review` / Reviews API posting inline comments | **Two `review-docs/` documents (EN + ZH) with `path:line` anchors** |
| CI's review verdict is visible on the PR itself | On a pass, one `doris-repo-review/v1` comment from the local account (commit sha, timestamp, model, findings, notes); on REQUEST_CHANGES, nothing - the documents stay local |
| 60-minute timeout | No hard timeout, but likewise do not let one round turn into unbounded digging |

---

## 13. Common traps

- **Treating "another Minor appeared" as non-convergence.** A PR of any size yields another Minor
  for as long as you keep looking. What has to stop moving is the *verdict* - see step 7. Two runs
  in a row reporting "did not converge" while the blocking findings were settled in round 1 is a
  broken criterion, not a deep PR.
- **Dispatching a subagent on a premise you never checked.** The premise check of step 4.1 costs
  one command; skipping it costs a whole agent, and the agent comes back having proved you wrong
  rather than having reviewed anything.
- **Believing the round-1 ledger deduplicates anything.** It is empty when round 1 starts. Use the
  two waves of step 5.1, or pre-seed it.
- **Overwriting the previous run's documents.** They are untracked, so an overwrite is permanent,
  and it destroys the only record of what was already considered and dismissed. Write
  `pr-<N>-review.<head7>.*` and let the symlinks move.
- **Comparing runs by commit hash after a rebase.** A re-reviewed branch is often rebased, so
  `git log old..new` lists the whole PR again and tells you nothing. Compare content with
  `git show <old head>:<path>` before claiming a finding is newly introduced.
- **Staying inside the diff when the evidence is in a dependency.** See ground rule 4a. If a
  finding's mechanism ends in "…and the library does X", open the library.
- **The local checkout is ahead of the PR head.** `commit check: ahead:N` means there are unpushed
  commits and **they are not part of the review**. This is the easiest thing for a reader to
  misread, so state it both in the document header and in the closing report.
- **Anchoring to the wrong side.** `changed_line_ranges.txt` gives **post-change** line numbers,
  which match what a file read shows in the current directory. A pure deletion has no line on the
  new side - anchor the seam line and note `(deleted, base line N)`.
- **Switching invalidates the current directory's incremental build.** `output/`, `be/build_*`, and
  `*/target/` are all built per commit, so switching to the PR head and back usually forces a
  rebuild. Warn the user before switching.
- **Uncommitted changes are not in the diff.** `git diff BASE...HEAD` only sees committed content.
  Alignment already guarantees no dirty tracked files at switch time, but the user may have edited
  something afterwards; anything in `worktree_status.txt` must be named in the documents' "Coverage
  and Limits".
- **Subagents racing on the ledger.** One file per owner exists precisely for this; always hard-code
  each subagent's own file name in its prompt.
- **Re-raising an issue that already has a comment.** CI forbids it, and so does a local run - read
  `pr_review_threads.md` first.
- **A subagent's conclusion cannot be taken at face value.** The main agent must read the code back
  to confirm it; any "if A then B" that cannot name a concrete scenario for A is downgraded or
  dropped.
- **Do not commit `review-docs/`.** The doris repository does not ignore it, and an automatic commit
  would slip it into the PR.
- **The PASS comment is public and signed with the user's name.** It goes to a public Apache PR
  from their GitHub account, so it is posted only after they have seen the exact body. Treat a
  script refusal as final rather than something to route around, and never "tidy up" the rendered
  body by hand - a program reads it.
- **A pass is not a merge approval.** The comment states that a local pipeline review found no
  Blocker and no Major on one specific commit. It carries no CI signal and no Apache sign-off, and
  the `<sub>` disclaimer line says exactly that - keep it.
- **Counts drift between the documents and the comment.** `--findings` must be the accepted
  findings of step 9, not the candidate count from the ledger; re-count from the written documents
  before posting.
