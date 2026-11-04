# Submodule pointers

A submodule pointer, such as `contrib/apache-orc`, is one line in the diff but stands for the submodule's own change. Development records what follows in the handoff file; the PR step collects it here only when there is no handoff file or it lacks it.

`scripts/diff_profile.py` lists each pointer apart, with the range it moves, the repository and branch from `.gitmodules`, and the commits and lines in between when the submodule is checked out; otherwise read the range in that repository (`gh api repos/<owner>/<repo>/compare/<old>...<new>`). Treat that change, usually a dependency PR, as part of this one, and note every commit the range carries, not only the fix.

Check, too, that the new commit is on the branch: doris-thirdparty squash-merges, so a pin taken from a PR's head is reachable only through `refs/pull/<N>/head` (`git ls-remote <url> | grep <sha>`), and the merged commit, which has the same tree, is the one to pin.

For a Bugfix, `references/facts/bugfix-origin.md` says how to compare the pin on each release branch.
