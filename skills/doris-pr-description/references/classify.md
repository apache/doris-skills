# Step 2: Classify the PR type

Pick one type by the change's purpose, not by the first verb of the title or the branch name.

| Type | Title tag | Use for | Required fields in Details |
|---|---|---|---|
| Bugfix | `fix` | Wrong results, crashes, unexpected errors, leaks, hangs, behavior that contradicts the docs | Frequency; Root cause; Why existing tests missed it; Fix; Other paths and branches |
| Performance | `opt` | Faster or cheaper, with no intended change in results | Why it was slow; Optimization; Results; Applicability and cost |
| Feature | `feature` | A capability users did not have: syntax, a function, a data source, a privilege, a system table, a switch for new behavior | Scope; Design; Usage; Default behavior; Compatibility. An issue is required |
| Enhancement | `improvement` | An existing capability made better: usability, errors, observability, limits, configurability | Before and after; Configs and defaults; Impact on existing users |
| Refactor | `refactor` | Restructuring with no intended behavior change; removing dead code | Moves vs. logic changes; Behavior change; Compatibility; Performance impact; Rollback |
| Test | `test` | Only test code or test infrastructure | Adding tests: Scenarios; What existing tests miss; Fails when broken. Fixing a test: Failure; Cause; Stability evidence |
| Build/CI/Chore | `chore` | Build, CI, tooling, code style, docs inside this repository (`README`, comments, `AGENTS.md`, skills), version bumps | Affected; Developer and release impact; License and third-party; Rollback |
| Revert | `Revert "…"` | Reverting earlier PRs, fully or partly | Why not fix forward; Original author notified; Follow-up |
| Release/Dependency | `deps` | Upgrading, adding, or pinning third-party dependencies | Versions; Upstream changes; Compatibility; Rollback |
| Other | `other` | Experiments, placeholders, CI trials; open them as Draft PRs | Why Other |

When two types seem to fit:

- The old behavior was a defect → Bugfix. It worked as designed and the PR makes it better → Enhancement.
- Success is measured in time or resources → Performance, also when it trades one resource for another, such as a larger index for faster queries; the trade-off goes in Applicability and cost. If behavior changes as well (as `Behavior changed` is defined under Check List in `references/write.md`), it is an Enhancement with a Results field.
- Users gain new syntax, a function, a data source, a privilege, or a switch that enables new behavior → Feature, even when it extends an existing feature. Between Feature and Enhancement, choose Feature. A config that tunes existing behavior, such as a threshold or a size, is not such a switch.
- The default moves to a new behavior, and a switch brings the old one back → Enhancement, unless users gain a capability they did not have.
- A defect fixed behind a switch that is off by default → still Bugfix; describe the switch in its Configs and defaults field.
- A flaky test caused by a real race in production code → Bugfix. Only test code changes → Test.
- A refactor needed for a fix belongs to the fix; say so in Fix and in Notes for Reviewers. Two unrelated purposes → suggest splitting the PR.

Then read `references/types/<file>.md`: what reviewers check for that type, what to write in each field, and what development must establish. The files are `bugfix`, `performance`, `feature`, `enhancement`, `refactor`, `test`, `build-ci-chore`, `revert`, `release-dependency`, and `other`. Each type's complete example is in `references/examples/<file>.md`, for when the draft is written.
