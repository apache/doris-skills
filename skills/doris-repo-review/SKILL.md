---
name: doris-repo-review
description: Review an Apache Doris PR from a local clone with the same multi-agent, shared-ledger convergence workflow as the CI Code Review Runner. Use when the user supplies a PR to `/doris-repo-review`, asks to review a Doris PR locally, or asks for the CI-style review flow. Safely align only the current worktree to the exact PR head, refuse to disturb tracked local changes, write equivalent English and Chinese review documents with verified path-line anchors, and never build, test, or edit source. Treat a review as pipeline-equivalent only when an explicitly selected Opus 5, Fable 5, or GPT-5.6 Sol reviewer runs at xhigh or higher.
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
python3 $S/verify-anchors.py --ctx "$CTX" --doc <en> --doc <zh>      # step 9: verify anchors
$S/post-pass-comment.sh --ctx "$CTX" --model <id> ... --dry-run      # step 10: PASS comment
$S/review-runtime-policy.sh check <model> <effort>                    # reviewer eligibility
```

| File | Purpose |
|---|---|
| `scripts/align-to-pr.sh` | Resolve the PR, diagnose how the current directory relates to it, align it to the PR head |
| `scripts/prepare-review-context.sh` | Produce the authoritative diff, new-side line ranges, required AGENTS.md list, existing comments, ledger skeleton |
| `scripts/verify-anchors.py` | Check that every `path:line` anchor really exists and that both documents expose the same finding IDs |
| `scripts/review-runtime-policy.sh` | The exact model and effort allowlist for a pipeline-equivalent review |
| `scripts/post-pass-comment.sh` | Render and post the machine-readable PASS comment; refuses everything that is not a pass |
| `references/prompts.md` | Subagent prompt templates (CI wording, carried over verbatim) |
| `references/doc-templates.md` | Templates for both documents, anchor format, verdict rule |
| `references/pr-comment-format.md` | The `doris-repo-review/v1` comment schema, field meanings, and how a program reads it back |
| `references/qualified-runtime.md` | How to select or delegate to a qualified lead and coverage reviewers |

Requirements: `git`, an authenticated `gh` CLI, `jq`, and `python3`. The clone must have full
history (`git fetch --unshallow` on a shallow one), because the authoritative diff is a three-dot
diff from the merge base.

---

## 0. Ground rules

Before reading source, read `references/qualified-runtime.md` and establish a qualified lead
reviewer. If it requires delegation, the caller delegates the whole task and does no review itself.
If no qualified runtime is available, produce local documents only and do not post a
pipeline-equivalent PASS comment.

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

If `BASE_SOURCE` is not `PR base sha (matches CI)`, the baseline differs from CI's and the
documents must say so.

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
downstream files that must be read alongside it, and the **specific question** a risk-focused
subagent has to answer.

An empty risk scan means you have not understood the PR yet - go back and read it; do not skip
this step.

---

## 5. Spawn the subagents

Split along the coverage the code-review skill requires, and **send them all in one message so
they run concurrently** (general-purpose subagents). Use the same qualified model and effort as
the lead; follow the coverage-reviewer rules in `references/qualified-runtime.md`:

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
state the ledger directory and the path of that subagent's own file.**

> **One implementation difference from CI**: CI uses a single `subagent_review_findings.md` with
> sections; locally, concurrent writes to one file collide on patch, so this becomes **one file per
> owner** under `ledger/`. The semantics are unchanged - a single shared source of truth, everyone
> reads all of it, each writes only their own, the main agent merges.

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

---

## 7. Convergence loop (at most 3 rounds)

One round = step 5 + step 6. Record the outcome in the `Convergence Rounds` table of
`main-merged.md`.

- Every subagent returned `NO_NEW_VALUABLE_FINDINGS` → go to step 8.
- New valuable candidates remain → start another round: **re-slice the coverage** based on what
  this round taught you (do not re-dispatch the same split unchanged), and add risk-focused
  subagents for any newly suspicious mechanism.
- **Cap of 3 rounds.** If the cap is reached and new candidates still appear, finish normally but
  state in the verdict and in "Coverage and Limits" that **this review did not converge**.

---

## 8. Final sweep

Before writing the documents, walk explicitly through the changed-file list and the open-candidate
list:

- Was every changed file covered by at least one subagent? Cover the rest yourself.
- Does every suspicion have a conclusion?
- Does every applicable item in Part 1.3 of the code-review skill have an explicit conclusion?
- Is there anywhere you are still unsure about, or that may not have been investigated deeply
  enough? Investigate it now.

Only after the sweep may you write the documents.

---

## 9. Produce the two documents

Write them into `review-docs/` in the **current directory** (`mkdir -p` it if needed):

```
review-docs/pr-<N>-review.en.md
review-docs/pr-<N>-review.zh.md
```

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
  split, what was not verified locally (builds, tests, anything needing a real cluster), and the
  uncommitted changes from `worktree_status.txt` that were excluded.

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
   severity, and whether the rounds converged.
2. The `branch check` / `commit check` results - especially `ahead:N` (unpushed commits that were
   not reviewed).
3. **What happened to the PASS comment**: the URL when one was posted or updated, or the reason
   nothing was posted (the verdict was REQUEST_CHANGES, the PR head moved, the user said no).
4. **Where the current directory now stands**: with `ALIGN_MODE=switched` it is detached on the PR
   head, and `git checkout <PREV_REF>` restores it. **Do not switch back automatically** - the user
   may still want to read the code.
5. `review-docs/` **is not gitignored in the doris repository**, so **do not commit it
   automatically**; leave that to the user.

---

## 12. Mapping to the CI pipeline

| CI (code-review-runner.yml) | Local |
|---|---|
| `codex exec --goal` (gpt-5.6-sol, xhigh) | An explicitly selected qualified lead reviewer |
| checkout the PR head sha | `align-to-pr.sh` detaches **the current directory** to the same sha |
| `git diff BASE...HEAD` as the authoritative diff | Same, produced by `prepare-review-context.sh` |
| "PR changed while preparing" guard | The fetched sha must equal the API head sha, otherwise a re-run is required |
| `prepare_review_agents.py` collecting AGENTS.md | Same ancestor-directory algorithm, built into the script |
| Fetch existing inline threads (30 threads / 1200 chars) | Same jq |
| Text after `/review` = review focus | Free text after the PR URL → `--focus` |
| Single-file ledger with sections | A `ledger/` directory, one file per owner |
| Main risk scan → 1-3 full-review subagents + risk-focused → merge → ≤3 rounds | Identical |
| `gh pr review` / Reviews API posting inline comments | **Two `review-docs/` documents (EN + ZH) with `path:line` anchors** |
| CI's review verdict is visible on the PR itself | On a pass, one `doris-repo-review/v1` comment from the local account (commit sha, timestamp, model, findings, notes); on REQUEST_CHANGES, nothing - the documents stay local |
| 60-minute timeout | No hard timeout, but likewise do not let one round turn into unbounded digging |

---

## 13. Common traps

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
