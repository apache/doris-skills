# Step 4: Write the draft

## The draft file

Write the title and description by the rules below and the type's file, `references/types/<file>.md`, with its example in `references/examples/<file>.md`, and save them as a draft file:

- Name it `pr-<number>.md` for an existing PR, or `pr-<branch>.md` for a new one, with any `/` in the branch name replaced by `-`, here and in the issue draft below.
- Save it in the directory the user names; otherwise in a temporary directory outside the repository, so it can't be committed by accident.
- Line 1 is `Title: <title>`, line 2 is blank, and the description follows.

With a handoff file, start from its draft and keep its facts; this step settles the wording and the layout.

For a Feature without an issue (none in the handoff file, the commits, the branch name, or the PR's linked issues), also draft the issue as `issue-<branch>.md`, or `issue-<number>.md` for an existing PR, beside the PR draft and in the same format (line 1 `Title: <title>`, a blank line, the body), by `references/issue.md`, from the handoff file and the code. Until the issue exists, write `Issue Number: TODO(author): the issue in issue-<branch>.md`; step 6 creates the issue and puts in its number. This holds in Create and Update modes; Rewrite mode writes only the TODO.

## Title

`[<tag>](<scope>) <Summary>`. The repository's title check requires the `[type](scope)` prefix.

- **tag**: the type's tag: `fix` for Bugfix, `opt` for Performance, `feature` for Feature, `improvement` for Enhancement, `refactor` for Refactor, `test` for Test, `chore` for Build/CI/Chore, `deps` for Release/Dependency, and `other` for Other; a Revert takes the title in the last item. It must agree with `PR Type`.
- **scope**: lowercase. Name the area whose behavior changes, a module or feature such as `nereids`, `iceberg`, `load`, `storage`, `inverted index`, `datatype`, `regression`, or `thirdparty`, even when the code sits in a shared layer (an Iceberg-only change spread over several FE packages is `iceberg`). Use `cloud` for a change that matters only in cloud mode, the process (`fe`, `be`) for a change that spans several areas, and `build` or `ci` for build and CI work. For the spelling, follow earlier PRs in the same area: `git log --format=%s -20 -- <main path>`. When updating or rewriting a PR, keep the author's scope if it fits these rules.
- **Summary**: imperative mood, specific, under about 80 characters, no trailing period. Name what changes for users or developers, not the implementation.
- **Revert**: keep GitHub's default `Revert "<original title>"`. If the original title has no `[type](scope)` prefix, use `[revert](<scope>) Revert "<original title>"` so that the title check passes.

| Good | Bad | Problem |
|---|---|---|
| `[fix](iceberg) Fix NULL partition values after partition spec evolution` | `[fix](fe) Fix bug` | Says nothing about the change |
| `[opt](be) Use a bitmap for IN predicates on dense integer constants` | `[opt](be) Optimize in predicate` | Which optimization? |
| `[test](regression) Fix flaky test_routine_load_restart` | `[fix](test) Fix case` | The tag doesn't match the type, and it is vague |
| `[feature](iceberg) Support reading row lineage columns of Iceberg v3 tables` | `[Feature](Iceberg) support iceberg v3.` | Not lowercase, not specific, trailing period |

## Description

The description follows the repository's PR template, `.github/PULL_REQUEST_TEMPLATE.md`, which `develop-with-evidence` also drafts in. Read it from the checkout, keep its headings and line labels, and delete its guidance comments. Below is the same layout with each placeholder explained; the checker enforces it. If the checkout's template differs from it, as an older checkout with the old template does, follow the layout below and tell the user.

```markdown
### Background

<How the feature or module works today, in plain words, for a reviewer who doesn't know it.>

### What problem does this PR solve?

Issue Number: close #<issue> | #<issue> | None
Related PR: #<pr> (<relation>) | None
PR Type: <type from the table>

Problem Summary:

<The problem or need, who is affected, and the approach in one sentence.>

### Details

- **Change map:** <for a diff of more than about 300 lines: where the lines go>
- **<Field>:** <answer>

### Testing

- <test, suite, or command>: <what it shows>

### Notes for Reviewers

- <optional>

### Release note

<None, or one user-facing paragraph>

### Check List (For Author)

- Behavior changed: No | Yes (see Details)
- Does this need documentation: No | Yes (<doris-website PR or plan>)
- Pre-submission status: Ready | Partially verified: <what is not verified> | Not ready: <why>

### AI Disclosure

- Tool: <agent and model>
- Generated: <which parts>
- Human review: <what the author says they reviewed>
- Prompts: <optional: how the author directed the agent>
```

- **Background** opens every description, whatever the type. It gives a reviewer who doesn't know this part of Doris the context to follow the rest: what the feature or module is for, how the part that the change touches works today, and the terms the description uses (an `@incr` query, a delete-sign row, an SNII position window). Write two to four plain sentences, at most about 100 words, as you would explain it to a colleague from another module. Leave the problem and the fix to Problem Summary, and don't walk through code; name a class only when the reader needs it to find their way. When there is a user doc for the feature, link it. The type file says what Background covers for that type.
- **Header lines.** `Issue Number` is `close #N` when the PR resolves the issue, `#N` when it only relates to it, and `None` when there is no issue (never for a Feature). `Related PR` lists each PR a reviewer should know about as `#N (relation)`, separated by commas. Typical relations: introduced the bug, introduced the behavior this PR changes, builds on, depends on, conflicts with, follow-up to, supersedes, earlier attempt, reverted, alternative fix, same fix elsewhere, same change on `<branch>`, tested together with. Take them from the handoff file or the material that step 1 names, without searching GitHub for other PRs on the same problem, and write `None` when none is known. `PR Type` is one of `Bugfix`, `Performance`, `Feature`, `Enhancement`, `Refactor`, `Test`, `Build/CI/Chore`, `Revert`, `Release/Dependency`, and `Other`, spelled as here.
- **Problem Summary** is the abstract, and many reviewers decide from it alone whether and how closely to review: two to five sentences, at most about 120 words. Background has given the context, so start from the problem, and cover, in this order:
  1. The problem or need, and who has it.
  2. What the PR does about it, as users see it, with the property that the rest of the design depends on. For a switch or config, that is where it is set, whether it can change at runtime, and its default: `an FE config that can only be changed in fe.conf with a restart, so ADMIN cannot turn it off at runtime`. When the change itself is in another repository, say where it is and what this diff does with it: `the fix is in the ORC library (apache/doris-thirdparty#431); this PR moves contrib/apache-orc to it and adds tests`.
  3. When the diff is larger than sentence 2 suggests, why: what else the change had to handle, or that most of it is tests. Reviewers hold the summary against the size that GitHub shows, and a one-line switch next to 600 lines of code makes them suspect unrelated changes until they read the reason: `locking enable_audit_plugin alone is not enough: twelve other parameters can also skip statements, lose events, or cut the recorded text, so while the switch is on none of them can be set weaker than its default, and enforcing that is most of the code`.
  4. What existing users see after an upgrade if they change nothing, unless the type already makes it plain, as a bug fix does: `off by default, and with it off nothing changes`, or the exceptions.

  A side change, such as a small fix found on the way, gets a clause at most; its own field says the rest. Details go in fields.
- **Details** holds the type's fields as `- **Field:** answer`, in the order of the type file, after the Change map when there is one. Required fields always appear; conditional fields appear only when they apply. Most answers are one to three sentences. `None` is a valid answer when it is true; padding is not.
- **Change map** opens Details, in any type, when the diff has more than about 300 changed lines. It tells reviewers where the lines go, so that they can size the review and see that nothing in it is unrelated. Take the numbers from `scripts/diff_profile.py` (step 1) rather than counting:
  - First the split: the added and deleted lines of production code, tests, generated files such as regression `.out` files, and docs. Tests reassure reviewers rather than burden them, so when they outweigh the code, say so: a 1,000-line PR that is 900 lines of tests is a small review.
  - Then, when the production code has more than one part, the parts as a numbered list or a small table, in the order to read them: what each handles and why the change needs it, its size, and its main classes. Group by the problem a part handles, not by file or module; a file can serve two parts, and sizes may be approximate. Name each refactor or side fix the diff carries, so that nothing in it looks unrelated, and when each part is a commit, say so, since reviewers can then read commit by commit. In a Refactor, mark each part as a move or a logic change.
  - A submodule pointer is one line of the split but stands for the submodule's change: give the range it moves, the commits it carries, the size of their diff, and the part to review. When Details has no Change map, as for a small diff, say this in Notes for Reviewers.

  Keep it to about 200 words, one line per part. The reasons for single edits go in Notes for Reviewers, and a file-by-file walkthrough is still out (Writing rules).
- **Testing** says what was run, what it shows, and where it ran (locally or in CI) when that is known, naming the test files or suites. Don't guess where a test ran, and leave out lint, format, and build-only checks, which CI runs anyway. Attribute runs that only the author reports, in the description or in commit messages, to the author (`The author reports 54 passing BE tests on an ASAN build`), and name the commit when the run predates later commits. `VERIFIED` runs in the handoff file count as test output: state them as run, and say where and, when it is not the head, on which commit. When that commit is no longer in the branch, as after a rebase, say the run predates the rebase instead of giving a hash that reviewers can't find. Benchmark numbers name the revision they were measured on in the same way. The type file says what the tests must prove.
- **Notes for Reviewers** is optional. Use it for diffs over about 200 changed lines or across modules, and whenever a reviewer needs something outside the diff, such as an open PR that changes the same code or the change behind a submodule bump: the reason for each non-obvious edit (a removed check, a changed constant or default, deleted code), what the author is unsure about, and where to start reading when Details has no Change map. "Why this line?" is one of the most common review questions, and usually only the author knows the answer; giving it here saves a review round. Omit the section when there is nothing to say.
- **Release note** is one paragraph for users: what they will notice and, for behavior changes, the old behavior, the new one, and how to keep the old one. Compare with the latest release, not with `master`: when `master` has replaced the code a release runs, describe what users upgrading from that release will see. Write `None` when no user of a release, past or upcoming, will see a difference: refactors, tests, CI, fixes for bugs that exist only on `master` or a feature branch, reverts of unreleased changes, and optimizations whose gain has not been measured. A change to a feature that no release has shipped yet needs a note only when it adds something users set or see on its own, such as a config or session variable. Leave out PR links and author names.
- **Check List (For Author).** `Behavior changed` is `Yes` when users or clients can observe a difference other than what the PR sets out to do (the fixed bug, a new capability seen only by those who use it, a speedup): other results, errors or messages, defaults, EXPLAIN, SHOW, or profile output that tools may parse, new ways to fail, or anything that changes after an upgrade for users who change nothing. A new config or session variable that changes nothing at its default is part of the new capability, even though it appears in `SHOW VARIABLES` or among the configs. The resource cost of an optimization belongs in Applicability and cost, not here. When it is `Yes`, explain the difference in a `Behavior change` field in Details, which any type may add; in an Enhancement, Before and after already covers it. User documentation lives in `apache/doris-website`; link the docs PR or state the plan.
- **Pre-submission status** tells reviewers how far the author verified the change before asking for review, so that they can compare it with what CI and their own review find. `Ready`: the evidence in Testing covers the PR's key claims on the current head, and no known problem is open. `Partially verified: <what is not verified>`: a needed verification has not run, ran only in part, or ran on a commit that later changes affect. `Not ready: <why>`: a known problem is unresolved or a needed check fails; open such a PR as a Draft. Take it from the handoff file when there is one, after checking it against the head, and update it whenever the description is updated for new commits. Rewrite mode judges it as `references/rewrite.md` says.
- **AI Disclosure** names the tool and model, and which parts were generated: code, tests, this description. When different tools or models wrote different parts, name each with its part, separated by semicolons. In Create and Update modes, the handoff file's AI involvement says which tool generated which parts. Fill `Human review` only with what the author states, and never assess it yourself. Write `not stated` for anything the author has not said, rather than a TODO. Rewrite mode follows `references/rewrite.md`.
- **Prompts** is the one optional line of the AI Disclosure. It tells reviewers how the author had the agent develop the PR: the task as first given, the constraints or approach the author chose, and the corrections made after reviewing the agent's work. A reviewer learns which decisions were the author's and what the agent was asked to do, context the code cannot show. Write it only from the author's own messages: this conversation, if the change was developed in it; the Direction notes in the handoff file, which paraphrase the author's instructions during development; or prompts or a session transcript the author gives you. Paraphrase in English, in order, in one to three sentences or a numbered list of up to five items, about 80 words at most. Leave out the agent's replies and plans, routine requests such as asking for this description, and anything private (see Keep it public). When the prompts are not available, as in Rewrite mode unless the original description includes them, omit the line instead of writing `not stated`; never reconstruct prompts from the code.

## Issues

- **Feature**: an issue is required. It holds the use case and the proposed design; link it with `close #N` or `#N`. When there is none, Create and Update modes draft one that describes the approach as built (the draft file, above) and open it before the PR; design discussion can continue there.
- **Every other type**: an issue is optional. A required field may be answered in the PR or in the linked issue. When the issue already answers it, write a one-line summary with a pointer (`Always reproducible; reproduction SQL in #12345`) instead of copying it. Keep the field label in the PR either way, so that reviewers and the triage bot find every answer in one place. Point to the issue only after reading it and confirming the answer is there.

## Writing rules

- **Write the first screen for triage.** The title, Background, and Problem Summary, with the Change map right after them, are what many reviewers read before they decide whether and how to review. Together they say what the PR does, why the diff is the size it is, and what changes for existing users. Everything below them is reference that reviewers consult while reading the code, so lead each later field with its conclusion.
- **Say what the diff cannot show**: the reason, the alternatives, the risk, what was tested, and what is not covered. Don't restate the diff: no file-by-file walkthrough, no list of functions touched, no "Changes" section. The Change map is not a restatement: it groups the diff by purpose and gives the sizes, which the diff doesn't show.
- **Be specific.** Name the config, function, SQL, error message, version, or number. On their own, "improve", "optimize", "some issues", and "edge cases" say nothing.
- **Keep it short.** Reviewers read every line you add. The checker counts the prose, leaving out Background and the Change map (which have their own limits), the header lines, tables, code blocks, the Check List, the AI Disclosure, and `TODO(author)` markers, and warns above 500 words (900 for a Feature). When it warns, cut what the diff already shows, lists of files and functions, and anything said twice. Keep what reviewers can't get elsewhere: the reason, the risks, the numbers, and what is not covered. If nothing of the first kind is left, keep the length; the warning is a prompt, not a limit.
- **State only what you can trace** to the diff, the commits, the handoff file, the issue, test output, or the user. Never invent numbers, frequencies, test runs, CVE IDs, affected branches, or other people's agreement. List only tests that actually ran, and say where; if a test was added but not run, say whether a CI pipeline will run it, which `references/facts/existing-tests.md` shows how to check.
- **Write in English**, in plain sentences. Put identifiers in backticks, and SQL or configs in fenced blocks. No emoji, no headings beyond the template, and don't open a section with "This PR".
- **Keep it public.** The description becomes the squash commit message, so leave out internal tracker IDs such as JIRA keys, private links, and customer names.
- **Mention people deliberately.** `@login` notifies them; use it where needed, such as telling the original author about a revert.
