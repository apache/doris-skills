# Step 1 with a handoff file

In Create and Update modes, look for the handoff file before anything else: `$(git rev-parse --path-format=absolute --git-common-dir)/pr-handoff/<branch>.md`, where `<branch>` is the output of `git branch --show-current`, or the PR's `headRefName` in Update mode. A development skill such as `develop-with-evidence` leaves it there: a description draft in the layout of the PR template, the goal and the decisions with their alternatives, the parts of the change, the reasons for non-obvious edits, the existing tests, the evidence, and how AI was used. If it is missing while the `pr-handoff` directory holds other files, one of them may belong to this change under another branch name; ask the user. If there is no handoff file, collect the facts as step 1 in SKILL.md routes.

## Its facts are the source

Take the facts in the handoff file as given, and don't collect them again: the PR type, the title, Background, the problem and the approach, `Issue Number` and `Related PR`, the parts of the change, the decisions, the answers to the type's fields (for a Bugfix, the other paths and the release branches too), the existing tests, the documentation plan, the evidence, the pre-submission status, and the AI involvement. Its draft is where the description starts; step 4 settles the wording and the layout by `references/write.md`.

Where each part goes:

- The decisions feed the Design field and, for a Feature without an issue, the issue.
- The parts of the change feed Problem Summary and the Change map.
- The reasons for non-obvious edits feed Notes for Reviewers.
- The existing tests feed Why existing tests missed it, What existing tests miss, and Testing. A test that asserts the changed behavior and that the diff leaves unchanged is a stop condition (step 3).
- Only entries with status `VERIFIED` are runs that Testing may state. `NOT_RUN` and `FAILED` entries are gaps for the pre-submission status, and a `FAILED` one is also a problem to show the user (step 3).
- The pre-submission status and the AI involvement feed the Check List and the AI Disclosure, and the Direction notes feed the Prompts line.

## What the PR step still does

1. **Find the range.** Find the remote that points to `apache/doris` with `git remote -v` (called `upstream` here):

   ```bash
   git fetch upstream master
   base=$(git merge-base HEAD upstream/master)
   ```

   `<head>` below is `HEAD`. In Update mode, read the PR's current title and description (`gh pr view <N> --repo apache/doris --json title,body,headRefName,baseRefName,isDraft,url`); when its branch is not checked out here, fetch its head into a named ref (`git fetch upstream '+pull/<N>/head:refs/remotes/upstream/pr/<N>'`) and use that ref in place of `HEAD`, in the merge base too. Skip a fetch when the refs you need are already there and current.
2. **Check that the file is current.** The `Updated` line names the commit the file describes, and each evidence entry the commit it ran on. `git diff --stat <commit> <head> -- <the code and tests it covers>` shows what changed since, and also covers a rebase, after which the commit is no longer in the branch. When nothing changed, the facts hold. Otherwise the facts about the changed code are stale: treat stale evidence as `NOT_RUN` and list the stale facts for the user (step 3), who may run the checks again or update the handoff file with the development skill.
3. **Count the lines** for the Change map: `python3 <this-skill-dir>/scripts/diff_profile.py "$base..<head>"`. If the profile shows production files that no part in the handoff file accounts for, show them to the user (step 3).
4. **Collect only what the file lacks.** For a fact the description needs that the file doesn't hold, use the file in `references/facts/` that covers it, and say in the final report which facts were collected this way.
5. **Update mode: read the review threads.** Answers already given to reviewers belong in the description; `references/facts/basics.md`, "Review threads", shows how to read them.

The author's statement on how much of the AI-generated work they reviewed comes from the user in step 6.
