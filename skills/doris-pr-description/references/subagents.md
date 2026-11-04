# Handing fact collection to subagents

When the environment offers subagents, hand them the collection below, which reads a lot and comes back as a short answer, so that the main session keeps the conclusions and not the file dumps. With a handoff file there is usually little to collect. Without subagents, do the collection yourself, by searching first and reading line ranges.

| Fact | Give the subagent | Ask for |
|---|---|---|
| The parts of a large diff, without a handoff file | the range, the output of `scripts/diff_profile.py`, and `references/facts/basics.md` | the parts by the problem each handles, in reading order, with sizes and main classes; anything that looks unrelated |
| Existing tests and CI coverage | the changed classes and functions, and the SQL, configs, or error text users see; `references/facts/existing-tests.md` | the closest tests at each layer, with what they set up and assert and the gap; the pipelines that run them, with the config lines; tests that assert the changed behavior, and whether the diff updates them |
| Where a bug came from, and the release branches | the faulty expression and its file; `references/facts/bugfix-origin.md` | the PR that introduced it; for each branch, whether it has the bug, doesn't, or couldn't be checked, with the evidence |
| A submodule pointer | the pointer and its old and new commits; `references/facts/submodules.md` | the commits the range carries, the size of their diff, and whether the new pin is on the branch |
| Review threads, in Update mode | the PR number | each question reviewers asked and the answer given, with links, leaving out bot comments |
| The original description, in Rewrite mode | the PR number and the final range | each claim, and whether it still holds, with the evidence |

A subagent knows only what the brief tells it: give it the goal, the facts already known, and the files or commands it needs, and ask for conclusions with `path:line` or command output to back them, not whole files or logs.

Keep in the main session: the PR type, the decision to stop and ask, the draft, the checker, and publishing. Before a subagent's finding goes into the description or stops the workflow, check the lines or the output it cites.
