# Step 3: Stop and ask

Stop and ask the user when:

- **The working tree has uncommitted or untracked changes** (Create mode; `git status --porcelain`), other than the local environment edits in the next item. Only commits are described and pushed, and a new test or `.out` file that was never added is the usual case. Ask whether to commit them or leave them out.
- **The diff carries unrelated changes**: formatting churn in untouched code, unrelated files, or local environment edits (`conf/`, `custom_env.sh`, `regression-test/conf/regression-conf.groovy`, `hooks/`, `AGENTS.md` edits made for a worktree). Ask to remove them or split the PR.
- **An existing test asserts the behavior this PR changes, and the diff leaves it unchanged.** It will fail in CI. Name the test and ask whether to update it before the PR is opened.
- **The handoff file holds a `FAILED` entry or facts gone stale**, or the line profile shows production files that none of its parts accounts for. Show them; the user decides whether to fix the code, run the checks again, update the handoff file, or describe the gap.
- **You find a likely problem in the change** while collecting facts: another path with the same bug, a test the change will break, a compatibility or security risk. Show it to the user with its evidence; they decide whether to change the code or describe the problem.
- **A required fact is unknown and cannot be derived**: how often a bug occurs, benchmark numbers, which tests actually ran.

Ask once, listing every missing fact and problem together.

Rewrite mode never stops; `references/rewrite.md` says what it records instead.
