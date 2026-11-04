# Collecting the facts without a handoff file

Read the change itself, not only its title.

## The change

For the current branch, find the remote that points to `apache/doris` with `git remote -v` (called `upstream` here):

```bash
git fetch upstream master
base=$(git merge-base HEAD upstream/master)
git log --reverse --format='%h %s%n%b' "$base"..HEAD
git diff --stat "$base"...HEAD
git diff "$base"...HEAD -- <path>          # read the core change closely
```

For an existing PR:

```bash
gh pr view <N> --repo apache/doris --json number,title,body,author,state,isDraft,createdAt,baseRefName,headRefName,additions,deletions,changedFiles,files,commits,closingIssuesReferences,url
git fetch upstream master '+pull/<N>/head:refs/remotes/upstream/pr/<N>'
base=$(git merge-base upstream/pr/<N> upstream/master)    # the code before the PR
git diff --stat "$base"...upstream/pr/<N>
git diff "$base"...upstream/pr/<N> -- <path>              # read the core change closely
```

Read the diff from the fetched ref, path by path, rather than with `gh pr diff`, which prints the whole diff at once, generated files included. Fetch into named refs, as here, rather than reading `FETCH_HEAD`, which any other fetch in the same clone overwrites. Skip a fetch when the refs you need are already there and current, for example because the user fetched them for you.

For a large diff, start from the profile below, find the core change (usually the largest production files), and read those hunks closely; skim tests and mechanical edits. Regression output files (`.out`) are generated and need no close reading, but grep them for any output the PR changes, such as an error message or EXPLAIN text.

## What to gather

- **The background a reviewer needs**, for Background: how the feature or module works today, the part of it the change touches, and the terms the description will use. Take it from the code, the linked issue, design docs, and the user docs in `apache/doris-website` (`gh search code --repo apache/doris-website '<term>'`).
- **Where the lines go**, for Problem Summary and the Change map. `python3 <this-skill-dir>/scripts/diff_profile.py "$base..<head>"` prints the added and deleted lines of production code, tests, generated test output, docs, and build files, overall and for each commit, with the largest files of each kind. The kind comes from the path, so correct it where a file says otherwise, such as a test utility under `src/main`. A submodule pointer, such as `contrib/apache-orc`, is one line in the diff but stands for the submodule's own change; `references/facts/submodules.md` says how to read it. Then sort the production code into parts by the problem each handles; the commits and the classes the core change adds are the usual starting points. When a part is something the title doesn't lead a reviewer to expect, find out why the change needs it: that reason belongs in Problem Summary.
- **The linked issue**, from `closingIssuesReferences`, `#N` in the body or commits, or the branch name: `gh issue view <N> --repo apache/doris --json title,body,state,comments`. A `#N` may be a PR rather than an issue; `gh api repos/apache/doris/issues/<N> --jq '.pull_request != null'` prints `true` for a PR.
- **Related PRs**, for the `Related PR` line, from the material at hand: the PRs that the description, the commits, or the linked issue name; the PR that introduced a bug (`references/facts/bugfix-origin.md`); the PR a Revert reverts; the PRs the diff builds on or depends on; and the same change on other branches, whose cherry-picks keep the PR number in the subject. Don't search GitHub for other PRs on the same problem. Ignore the PR itself.
- **Review threads** (Update mode only). Answers already given to reviewers belong in the description: `gh pr view <N> --repo apache/doris --comments`, and `gh api repos/apache/doris/pulls/<N>/comments --paginate` for inline comments.
