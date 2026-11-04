# Using subagents to keep the main session's context small

When the environment offers subagents, hand them the evidence gathering that reads a lot, comes back as a short conclusion, and changes no code. The main session receives only the conclusions and where they point, so that long stretches of code, logs, and search results stay out of it. Without subagents, do the work yourself as usual: search first, then read line ranges, and read only the end and the failing parts of a log.

## Work to hand to subagents

| Stage | Work | Ask for |
|---|---|---|
| 1, 2 | Digesting a long issue, discussion thread, or design document | The requirements, the settled conclusions, and the open questions, each with its source |
| 2 | Tracing callers, shared implementations, parallel paths, and alternative entry points | `path:line` for each, with one sentence on its role; which share this defect and which only look similar |
| 1, 3, 5 | Building, deploying, and running tests, especially those with long logs | The command, the exit code, where the binaries came from (the commit or the build time), the number of cases actually run, and where the failed assertions and the key log lines are |
| 3 | Finding the existing tests closest to the change and the tests that assert the changed behavior; checking whether CI runs the new tests | The test names, with the data each sets up, the user it connects as, and what it asserts, and the gap that let the problem through; the pipelines that will run the new tests, with the config lines that show it |
| 3 | Cross-branch checks that the project requires, such as which release branches have the defect for a Doris Bugfix | For each branch: has it, doesn't, or couldn't be checked, with the evidence |
| 4 | Checkpoints that need wide evidence gathering, such as parallel paths, protocol definitions on each release branch, and persistence and replay paths | Each finding, with `path:line` evidence |

## Work that stays in the main session

- Whether the defect is real, the root cause, the choice of approach, every code change, the status of each piece of evidence, and the conclusions you tell the user and write into the handoff file.
- Targeted reverts and mutations: they change code in the working tree. Hand them out only when the subagent has its own working tree; in Doris, a separate working tree means a full rebuild, which is usually not worth it.
- Self-review conclusions: a subagent's findings are only evidence for the self-review. The main session rules on each one against the source, a run, or the contract, and never calls them an independent review.

## Briefs and results

- A subagent knows only what its brief tells it. State the goal, the facts already known, and the directions already ruled out; give the paths to read or the commands to run; and bound the scope.
- Ask for conclusions with `path:line` or log locations only, not whole stretches of code or logs.
- Let only one subagent at a time build or start a cluster, and in a shared working tree, don't let subagents change code.
- When results come back, spot-check the lines or logs cited by the key conclusions that will go into the handoff file or affect the approach. Record execution results in the handoff file in the format of `references/evidence-entry.md`, with the command actually run as the `Method`.
