---
name: doris-pr-description
description: Write, rewrite, or check the title and description of an Apache Doris pull request against the Doris PR standard. Takes the facts from the handoff file that development left when there is one, and collects them from the diff, commits, linked issue, and existing tests otherwise; classifies the PR type, fills that type's required fields, drafts the issue a Feature needs, validates the draft with a bundled checker, and creates or updates the PR on GitHub only after the user confirms. Use whenever the user wants to open, create, submit, or update a Doris PR; write, fix, or improve a PR title or description; prepare a branch for review; rewrite an existing PR's description for comparison; or check whether a description meets the standard. Also use for short requests in any language, such as "open a PR", "write the PR description", or "is this PR description good enough?", even when the standard is not mentioned.
---

# Writing Apache Doris pull requests

Reviewer time is the scarcest resource in the Doris community. A PR description exists so that a reviewer can decide, in about a minute, whether the change is worth reviewing, what to look at first, and how much time it will take. That minute goes to the title, Background, Problem Summary, and the size of the diff that GitHub shows beside them, so together they must say what the PR does, why the diff is as large as it is, and what changes for existing users. Reviewers often don't know the module or feature a PR touches, so every description opens with a short Background that gives them the context. AI review already concentrates on logic errors; what it almost never comments on is why the change is needed and why this approach was chosen. Only the author can supply those answers, human reviewers spend nearly half their comments asking for them, and this standard puts its weight there.

The standard applies to PRs against `master` of `apache/doris`. Cherry-picks to release branches keep the original PR's description and are out of scope.

## Modes

| Mode | When | GitHub |
|---|---|---|
| Create | Open a PR for the current branch, and the issue a Feature needs when it has none | Push and create after the user confirms the drafts |
| Update | Improve the title or description of the user's own PR | Edit after the user confirms |
| Rewrite | Rewrite any PR's description for comparison or evaluation | Never; write files only |
| Check | Judge whether an existing description meets the standard | Never; report only |

Publishing is visible to the whole community, so when in doubt, draft and ask.

## Reading this skill

Paths are relative to this skill's directory. Read a reference file when the step you are on calls for it, and only the files that the mode, the PR type, and the change need; don't read ahead. A file read earlier in the session needn't be read again unless the context has been compacted since.

A development skill such as `develop-with-evidence` reads `references/development.md` and the files it points to, not this workflow.

## Workflow

1. **Collect the facts.**
   - In Create and Update modes, look for the handoff file that development left, by `references/handoff-intake.md`. When there is one, its facts are the source: don't collect them again. That file says what the PR step still does.
   - Without a handoff file, and always in Rewrite and Check modes, collect the facts by `references/facts/basics.md`. Add `references/facts/existing-tests.md` for a PR that changes code, `references/facts/bugfix-origin.md` for a Bugfix, and `references/facts/submodules.md` when the diff moves a submodule pointer.
   - In Rewrite mode, read `references/rewrite.md` before collecting; where it differs from the other files, it wins.
   - When the collection is large, such as a large diff, several release branches to check, or long review threads, `references/subagents.md` says what to hand to subagents.
2. **Classify the PR type.** Take it from the handoff file; otherwise classify by `references/classify.md`. Then read the type's file, `references/types/<file>.md`, where `<file>` is `bugfix`, `performance`, `feature`, `enhancement`, `refactor`, `test`, `build-ci-chore`, `revert`, `release-dependency`, or `other`.
3. **Stop and ask** if a condition in `references/stop-and-ask.md` applies.
4. **Write the draft** by `references/write.md`, with the type's example in `references/examples/<file>.md`. For a Feature without an issue, also draft the issue by `references/issue.md`.
5. **Run the checker** and fix what it reports, by `references/check-and-publish.md`.
6. **Show the drafts, and publish only after the user confirms**, by the same file.

In Check mode, do steps 1 and 2, then follow the Check mode part of `references/check-and-publish.md`.
