# Choosing verification by change type

Pick the type from the quick reference first, then read only that type's strategy file (all of them are under `references/change-types/`). Classify by behavioral promise and risk; when one change spans several types, add only the checks for the risks each extra type brings. Prefer the project's existing tools.

When the project's PR standard has its own type table, take the PR type from the standard and the verification strategy from this directory; where the two don't map one to one, choose and combine by the actual risk.

## Quick reference

| Change type | Default evidence | Add when there is a specific risk | Strategy file |
|---|---|---|---|
| Bugfix | The exact error and the expectation; when it can reasonably be reproduced, the same test failing on the baseline and passing with the fix | Related entry points, boundary inputs, states, and concurrent timing; a targeted revert of the fix when the test could pass falsely | `bugfix.md` |
| New feature / API | The requirement turned into observable acceptance items; the main path, the new failure conditions, and the default behavior verified | Privileges, state transitions, persistence, interface compatibility, the supported ways of calling it | `feature.md` |
| Enhancement of an existing feature | The exact before-and-after difference on the same input: output, errors, limits, defaults | For a changed default, the actual value after an upgrade, and whether old persisted settings override the new default; old behavior where compatibility is promised | `enhancement.md` |
| Refactor | The affected code held in place by existing behavior tests, the build, and type checks; the callers checked | Behavior tests for coverage gaps; differential verification when equivalence is in doubt | `refactor.md` |
| Performance optimization | Correct results; a comparable baseline; the target workload and one plausible unfavorable case | The dimensions this algorithm is sensitive to, such as input size, distribution, threads, memory, and I/O | `performance.md` |
| Test / CI | The check runs and keeps its original power to detect failures | When assertions, filters, skips, or exit codes change, a known failing sample to verify detection | `test-ci.md` |
| Config / dependency / build | The parsed result, the lockfile or the toolchain, and the affected startup and build paths | Old configs, installs and upgrades, supported platforms, and runtime behavior that the change's promises involve | `config-build-migration.md` |
| Data migration / storage format | A run on disposable, representative data; the data invariants and the failure behavior verified | Extra checks only for the compatibility, rerun, resume, and rollback paths that are promised | `config-build-migration.md` |
| Frontend / interaction | The target interaction performed, with the state and the visible result checked; a visual check for layout changes | Keyboard, async and failure states, responsive layout, and accessibility behavior that this change affects | `frontend-and-low-impact.md` |
| Revert | The original problem gone after the revert, such as a failing test passing again | Whether code merged later depends on the reverted part; what a partial revert keeps | `revert.md` |
| Wording / comments / pure formatting | The content and the diff checked; rendering, links, or syntax where needed | Escalate for executable examples, config keys, or template logic, and verify what they actually do | `frontend-and-low-impact.md` |
