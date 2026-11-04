# Where a bug came from, and which release branches have it

For a Bugfix, the Other paths and branches field names the release branches that have the bug and the PR that introduced it. Development records them in the handoff file; the PR step collects them here only when there is no handoff file or it lacks them.

Doris squash commits end with `(#<PR>)`, so the PR that introduced a bug is usually one `git log -S` away. Backports to release branches are cherry-picks with new commit hashes that keep the PR number in the subject, so search the subject, and when in doubt read the code on the branch. Check the release branches still maintained; the root `AGENTS.md` lists them in its upgrade path.

```bash
git log -S '<buggy expression>' --format='%h %s' -- <file>
git fetch upstream branch-4.1                                   # one per release branch
git log upstream/branch-4.1 --oneline --grep '#<introducing PR>'
git show upstream/branch-4.1:<file> | grep -n '<buggy expression>'
```

If a branch cannot be checked, say which one rather than guessing. If the fix depends on another PR, check that PR on each branch in the same way, since a cherry-pick needs it too. When the fix is a submodule bump, compare each branch's own pin with the new one: moving the pin there carries every commit in between, and those may need Doris changes the branch lacks. Fixes in some areas are also picked to feature branches (PR titles such as `branch-<name>: pick ...`); when the area's history shows such picks, check those branches as well.
