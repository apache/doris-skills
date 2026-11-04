# The handoff file

The handoff file is what development hands to the PR step: a PR description draft, plus the facts, evidence, and decisions behind it. When the environment has the project's PR description skill (such as `doris-pr-description` for Doris), that skill reads the handoff file: it takes the facts in it as given and doesn't collect them again, adds only the facts that can be known only when the PR is opened, and owns the final description and the publishing. Without such a skill, the developer can use the draft directly. So everything that skill lists for the handoff (doris-pr-description's `references/development.md`) must be established and written down during development.

Don't add verification reports, internal journals, or skill files to the repository. The handoff file lives inside the `.git` directory and never enters the codebase.

- **Location:** `$(git rev-parse --path-format=absolute --git-common-dir)/pr-handoff/<branch>.md`, where `<branch>` is the output of `git branch --show-current`. A branch name with `/` makes subdirectories, so create the directory before writing. Inside the `.git` directory the file is never committed. All worktrees share one `.git` directory and their files are kept apart by branch, so the file can still be found from a new session or after its worktree is deleted. When the user names another location, use that.
- **Branch:** before writing, check that HEAD is on a named branch. On a detached HEAD (for example, a worktree created straight from `upstream/master`), create a branch first or ask the user to name one. When the branch is renamed, move the handoff file to the new name too.
- **Language:** English. Talk with the developer in the user's own language as usual.
- **When:** create it when the task starts, and write stage 1's decisions into it right away; update it after re-verifying, changing code, or rebasing. Mark stale evidence `NOT_RUN` with the reason, rather than deleting it.

Structure:

````markdown
# PR handoff: <branch>

Updated: <date>; code: <commit>, or <commit> plus uncommitted changes in <paths>
PR type: <the type in the project's PR standard, if it has one>

## Description draft

Title: <the PR title, by the project's title rules>

<The repository's PR template, with its headings and line labels and without its guidance comments; see below.>

## Goal and decisions

- Goal: <expected behavior, contracts to keep, the change's boundary, and the observable results that mean it is done>
- Decisions: <each user-visible choice (syntax, names, defaults, configs, privileges), the alternatives rejected, and why>
- Parts of the change: <each part the change grew into beyond its first idea, and the problem it handles>
- Reasons for non-obvious edits: <each removed check, changed constant or default, or deleted code, and why>
- Existing tests: <the closest existing tests at each layer and the gap that let the problem through; tests that assert the changed behavior and whether the diff updates them; whether CI runs the new or changed tests>

## Evidence

<Entries in the format of references/evidence-entry.md.>

## AI involvement

- Tool: <agent and model>
- Generated: <which parts: code, tests, this draft>
- Direction: <the developer's own instructions, in order: the task as first given, the constraints or approaches they chose, the corrections after reviewing. Paraphrased; no agent replies, nothing private.>
````

The draft's first line is the PR title (`Title: <title>`), and the body follows the repository's PR template: keep the template's headings and line labels, and delete its guidance comments. Cover the five parts below, each in its matching place in the template, such as Problem Summary and the type's fields, Testing, and the Check List of the Doris template. When the template has no matching place, use the closest section; when the repository has no template, organize the draft by these five parts:

1. **Problem or goal:** why the change is needed.
2. **Final change and behavior:** the approach and the behavior that results, in two to four sentences. Don't list files, functions, or lines one by one, and don't restate the diff.
3. **Verification:** the key commands or steps, their results, and the code version they ran on; highlight the evidence that tells right from wrong.
4. **Limitations and trade-offs:** what is unverified, performance regressions, compatibility changes, or open questions that need an answer.
5. **Pre-submission status:** `Ready`, `Partially verified: <gap>`, or `Not ready: <reason>`, as `references/stages/6-deliver.md` defines them.

Also put into the draft the background learned during development: how the feature being changed works today. For related PRs, write the relations known for certain from the work, such as the PR that introduced the defect, or the PRs this change depends on or builds on; don't search the code hosting platform for other PRs or issues on the same problem. Leave to the PR step only the facts that can be known only when the PR is opened, such as the line counts of the final diff, the review comments on an open PR, and the author's statement on how much of the AI-generated work they reviewed. Don't leave the other facts blank, and don't guess them. When the scope of the requirement changes, update the draft so that it doesn't still describe only the first version. Keep the full internal logs where they can be found when needed, and don't paste the whole history of repeated self-reviews into the draft.
