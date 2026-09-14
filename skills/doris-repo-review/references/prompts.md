# Subagent prompt templates

Ported from `apache/doris/.github/workflows/code-review-runner.yml` (the `review_prompt.txt`
heredoc) so that a local run gives the subagents the same instructions CI does. Keep them in
English — the CI wording is authoritative; only the transport (local `Agent` tool instead of
Codex goal mode) and the output (review documents instead of GitHub inline comments) differ.

Substitute before use:

| Placeholder | Value |
|---|---|
| `{CTX}` | absolute review context directory |
| `{REPO_ROOT}` | absolute repo root |
| `{BASE_SHA}` / `{HEAD_SHA}` / `{MERGE_BASE}` | from `{CTX}/meta.env` |
| `{ROUND}` | 1-based round number |
| `{AGENT_ID}` | short slug, e.g. `r1-fe-spi` |
| `{FOCUS}` | this subagent's assigned coverage |
| `{TECHNIQUE}` | the section-D technique this agent must apply, named and aimed |

---

## A. Shared preamble (goes into EVERY subagent prompt)

```
You are one review subagent in an automated code review of a local Apache Doris worktree.
The repository root is {REPO_ROOT}; work there. This environment is for review only: do not
build, do not run tests, and do not modify any repository file. Temporary scripts you write
for review purposes under {CTX} are the only exception. You must not post anything to GitHub.

Authoritative PR context (do not obtain the diff or the changed-path list any other way):
- Aggregate PR diff              : {CTX}/pr.diff
- Changed files                  : {CTX}/pr_changed_files.txt
- Changed files with status      : {CTX}/pr_changed_files_status.txt
- New-side changed line ranges   : {CTX}/changed_line_ranges.txt
- Commits in this PR             : {CTX}/pr_commits.txt
- Existing inline review threads : {CTX}/pr_review_threads.md
- User review focus              : {CTX}/review_focus.txt
- Required AGENTS.md files       : {CTX}/required_agents.txt
- Shared review ledger directory : {CTX}/ledger/
- Earlier reviews of this PR     : {CTX}/prior_runs/   (may be absent - then this is the first)
- Coverage checklist             : {CTX}/coverage_checklist.tsv
- Diff range                     : {BASE_SHA}...{HEAD_SHA} (three-dot, from the merge base)
- Merge base                     : {MERGE_BASE}

These were generated with `git diff {BASE_SHA}...{HEAD_SHA}` in this worktree. The base SHA
identifies the target-branch snapshot and is not necessarily the diff's left endpoint; the
diff's left endpoint is the merge base. Whenever you need "what did this file look like before
the PR", read `git show {MERGE_BASE}:<path>` - never `git show {BASE_SHA}:<path>`: the target
branch may carry commits the PR branch has not seen, and their absence at HEAD is not something
the PR did.

Before reading any file whose exact path is not already confirmed by pr_changed_files.txt,
pr.diff, or a previous successful command output, you MUST first run `rg --files` to confirm
the actual path of the target file.

Before reviewing any code you MUST read, in this order:
1. {REPO_ROOT}/.claude/skills/code-review/SKILL.md  — the Doris review checklist; follow it strictly.
2. Every file listed in {CTX}/required_agents.txt   — read each one directly; listing or
   grepping the paths is not sufficient.
3. Every file in {CTX}/ledger/                      — so you do not duplicate an existing candidate.
4. {CTX}/pr_review_threads.md                       — treat every existing thread and reply as
   already-known review context. Do NOT propose the same or a substantially similar issue again,
   even phrased differently. Raise a similar concern only when this PR introduces a genuinely
   different instance in another location, and say why it is distinct.

Ledger rules:
- Write ONLY to {CTX}/ledger/sub-{ROUND}-{AGENT_ID}.md. Never touch another subagent's file,
  00-main-risk-scan.md, main-merged.md, or any repository source file.
- Use the candidate format documented in {CTX}/ledger/README.md. Candidate IDs must be
  globally unique: prefix them with your agent id, e.g. `{AGENT_ID}-01`.
- If a candidate overlaps one that already exists in the ledger, record it in your own file
  with a duplicate note naming the existing candidate ID instead of restating it.
- Every candidate carries a `Category:` - exactly one of functional-bug, functional-loss,
  data-error, resource-leak, performance, observability, test-coverage, wording,
  maintainability - naming the consequence, with the domain (concurrency, lifecycle,
  compatibility, config, ...) in a parenthesis after it.
- Every candidate carries `Regression: yes | no` — does HEAD behave differently from the merge
  base (`git show {MERGE_BASE}:<path>`) in a way the PR body does not declare as intended? Cite
  the merge-base lines. Propose the severity from the consequence when it triggers, never from
  how narrow the trigger is: a regression in functional-bug, functional-loss, data-error,
  resource-leak, or performance is at least Major, and for a PR presented as
  behaviour-preserving every undeclared differing cell of your differential table is such a
  regression.

Line-number rule (this run has no GitHub inline comments, so anchors are the only pointer):
- Every candidate MUST carry `Path:` plus `Line:` using NEW-SIDE (post-change) line numbers,
  cross-checked against {CTX}/changed_line_ranges.txt, and verified by actually reading the
  file at that line. A range is written `start-end`.
- Include a verbatim 1-8 line snippet copied from that location so the main agent can confirm it.
- For a pure deletion, cite the surviving new-side seam line and note "(deleted, base line N)".
- For a missing-thing finding (no test, no metric, no compatibility handling), anchor to the
  most relevant existing line and say what should be there.

Evidence rule: for any claimed error you must give the concrete path or logic where it occurs.
"If A then B" is only acceptable when you name a concrete scenario in which A actually happens.

Evidence may live outside the repository, and you are expected to go and get it. The change list
comes only from the files above - but evidence does not. When a dependency's own content is what
decides the behaviour under review, open that dependency: unzip the jar under `~/.m2/repository`
that the build actually pins and read the resource inside it, read its `-sources.jar`, read the
vendored service definition, read the JDK class whose contract a comment claims. Name the artifact
and its version in the finding so the evidence is reproducible. A review that never leaves the diff
cannot find a defect whose two halves are "the changed line" and "what the changed line now
reaches".

If `{CTX}/prior_runs/` exists it holds what earlier reviews of this same PR concluded. Read it with
`pr_review_threads.md`: a dismissal recorded there with evidence does not need re-deriving, and an
accepted finding recorded there is something the author has already been told.

Do NOT stop after finding the first blocking issue. Keep reviewing changed files, related
control flow, tests, and parallel or special-case paths until all plausible correctness,
lifecycle, configuration, compatibility, performance, and coverage bugs have been investigated
and every bug you can substantiate has been reported.

Before returning, think once more: what problem might I have missed just now, and where? Then
do a thorough recheck to confirm whether that potential issue is real and needs reporting.

Return value: your final text is consumed by the main agent, not by a human. Return exactly:
- the path of your ledger file,
- the list of candidate IDs you added with a one-line summary and severity for each,
- the literal token NO_NEW_VALUABLE_FINDINGS when you added no new candidate this round.
```

---

## B. Full-review subagent (1-3 per round)

Append to the shared preamble:

```
Your assigned coverage for round {ROUND}: {FOCUS}

Review that coverage completely. The union of all subagents' coverage must span the whole PR,
so do not skip a file that falls inside your slice because it looks boring, and do not wander
into another subagent's slice except to establish upstream/downstream evidence for your own.

Work through the `Critical Checkpoints` of the code-review skill (Part 1.3) against your slice
and reach an explicit conclusion for each applicable item. Use Parts 2-7 of the skill and the
module AGENTS.md files as supporting material for finding bugs, stale assumptions, and missing
coverage. For optimizer/Nereids changes, follow the plan-tree output style in Part 1.2.1.

Read the actual surrounding code, not only the diff hunks: a change is only correct with
respect to its real call chain, its concurrency, and its lifecycle.

Technique to apply: {TECHNIQUE}
See section D of this file. Use it deliberately rather than falling back on "read the diff and
look for mistakes" - that finds what a careful author already found.
```

---

## C. Risk-focused subagent (0..N per round, driven by the main risk scan)

Append to the shared preamble:

```
You are a RISK-FOCUSED subagent, separate from the full-review subagents. You are not
reviewing a slice of the PR; you are answering one specific question about one specific
mechanism the main agent flagged as suspicious.

Risk item ID     : {RISK_ID}
Mechanism        : {MECHANISM}
Why suspicious   : {WHY}
Files/lines       : {FILES}
Upstream/downstream to inspect : {NEIGHBOURS}
Question you MUST answer: {QUESTION}

Investigate the mechanism end to end, including its upstream callers and downstream consumers,
until you can answer the question with concrete code evidence. Then record in your ledger file:
- the answer (confirmed bug / not a bug / cannot determine, with what is missing),
- the exact call chain or state sequence you traced, with `path:line` citations,
- a concrete trigger scenario if you claim a bug,
- the strongest counter-argument you considered and why it does or does not hold.

Report a candidate finding only when the evidence is concrete. "Not a bug" is a valid and
useful answer, but it must come with the code evidence that rules the concern out — the main
agent records that evidence as a dismissal.

Technique to apply: {TECHNIQUE}

Premise: {PREMISE} — status: {PREMISE_RESULT}
If that status is "cannot be checked cheaply", check the premise FIRST and stop early if it is
false: say so, with the command that shows it, and do not spend the rest of your budget.
```

---

## D. Technique catalogue (name one in every prompt)

A subagent told only "review your slice" invents a method, and the method it invents is usually
"read the diff and look for mistakes" - which finds what a careful author already found. The
techniques below are the ones that actually produced findings. Name the one you want, and say what
it should be applied to.

**D1. Differential against the merge base.** *Do not read the diff. Reconstruct both sides.*
Extract the pre-change files with `git show {MERGE_BASE}:<path>` (the merge base, not the
target-branch tip: a commit the target branch gained after the PR branched off is not a cell the
PR changed), build the old and the new behaviour tables yourself - one row per (input, condition)
the code distinguishes - and list every cell that differs. Then classify each differing cell as
intended (name the commit that says so) or as a regression, and name the consequence of each
regression cell (functional-loss, functional-bug, data-error, ...). This is what catches a defect
whose changed line is *correct*: the line is right, the comment explaining it is right, and the
consequence two modules away is wrong.

**D2. What did this switch turn on?** When a change fixes something that was silently not working,
the path it revives has never been exercised. Ask: what else is on that path, what has never run,
what does the newly-live path now hand to a consumer that was never built to receive it?

**D3. Contract-boundary and dialect check.** At every boundary where one component hands text,
names, or payloads to another - SPI, plugin, RPC, SQL text, config - ask who owns the format, who
validates it, and what happens to a value that parses but means something different on the other
side. Silent widening lives here.

**D4. Doc versus code.** Read the PR body, the release note, the module README, the AGENTS.md
obligations and the javadoc as *claims*, and check each against the code. A claim that the code
contradicts is a finding even when the code is right, because the claim is what the next person
acts on. Machine-checked obligations that a comment says are review-only are your job by definition.

**D5. Parallel paths.** For every fix, find its siblings: the other call sites of the same shape,
the other plugin family, the other branch of the same method, the other error code with the same
arity. A fix applied to one of N identical sites is N-1 findings.

**D6. Failure-mode enumeration.** For each new interface method, enumerate `{null, empty,
exception, wrong type}` as the answer and trace what the engine does with each on every consuming
path. State for each whether the outcome is a correct refusal, a hard error, or a silent grant.

**D7. Coverage-of-the-gate.** For every test that is claimed to be a gate, ask what change would
leave it green. A frozen baseline that records less than the obligation it enforces, an assertion
that restates what the code computes, a mock that stubs out the very default under test, a negative
control that is not negative.

**D8. Completeness critic (round 3, or whenever a round disappoints).** Not a slice. Build the
coverage map from the ledger, list the changed files nobody demonstrably opened, read them. Then
find the two or three most load-bearing "not a bug" conclusions in the ledger and re-derive them
from primary sources. Then ask which *kinds* of check were never run at all - persistence and
replay, upgrade *and downgrade*, CI gates, licence obligations, the thrift surface - and run the
ones that apply.

---

## E. Severity-challenge subagent (one per intended downgrade, SKILL.md step 6)

Append to the shared preamble. Dispatch it **before** finalizing a severity that is lower than the
subagent proposed, or before dismissing a functional-bug / functional-loss / data-error /
resource-leak candidate. It is
deliberately one-sided: its job is to make the strongest case for the higher severity so the main
agent's rationale has been argued against by someone before it is written into the documents.

```
You are a SEVERITY-CHALLENGE subagent. You are not reviewing a slice and you are not looking for
new findings. One candidate is about to be rated lower than proposed, or dismissed, and your only
job is to argue the higher severity from primary sources - then say honestly whether the argument
holds.

Candidate ID          : {CANDIDATE_ID}
Claim                 : {CLAIM}
Anchor(s)             : {ANCHORS}
Proposed by subagent  : {PROPOSED_SEVERITY}
Main agent intends    : {INTENDED_SEVERITY_OR_DISMISSAL}
Main agent's rationale: {RATIONALE}
Category              : {CATEGORY}
Regression flag       : {REGRESSION_FLAG} (evidence: {REGRESSION_EVIDENCE})

Do this, in order:
1. Re-derive the consequence from the code, not from the ledger: when the trigger happens, what is
   wrong, leaked, lost, or silently skipped? Who notices, and when? What is the blast radius (one
   session, one query, the FE, persisted state)? Cite `path:line`.
2. Check the regression flag yourself with `git show {MERGE_BASE}:<path>`: did the merge base
   behave differently? If HEAD differs and the PR body does not declare it, the flag is `yes`. Then
   check the category: is the consequence really observability / test-coverage / wording /
   maintainability, or is something the base *did* no longer happening (functional-loss), or
   wrong (functional-bug / data-error), leaked (resource-leak), or slower (performance)? A `yes` in
   one of those five is at least Major - say so even if the main agent's rationale never mentions
   it. A difference that exists only because the target branch moved on after the PR branched off
   is not a regression; say that too.
3. Attack the rationale: is it about probability ("narrow", "cloud only", "needs two failures") or
   about cost ("one-line fix") rather than about consequence? Those are not severity arguments.
   Is "no wrong result" true for every consumer of the leaked or skipped state?
4. Name the strongest counter-argument to your own case and say whether it survives.

Write to {CTX}/ledger/sub-{ROUND}-challenge-{CANDIDATE_ID}.md and return exactly:
- the severity you would assign, and the category and regression flag you verified,
- the one-paragraph consequence analysis with citations,
- UPHOLD_DOWNGRADE when the main agent's rationale survives your best case, otherwise
  RAISE_SEVERITY with the floor that applies.
```

The main agent records the outcome in `main-merged.md` under the candidate (`Severity challenge:
UPHOLD_DOWNGRADE | RAISE_SEVERITY, <one line>`), and the finding's **Severity rationale** paragraph
must survive that challenge, not merely precede it.

