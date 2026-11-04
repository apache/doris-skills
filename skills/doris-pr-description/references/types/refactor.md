# Refactor

Title tag: `refactor`. Use for restructuring with no intended behavior change: moving or splitting code, merging duplicates, renaming, removing dead or deprecated internal code. If users can observe any difference, it is not a pure refactor: list the difference under Behavior change, or move it to its own PR.

## What reviewers check

- Why now: what does this unblock or prevent? Doris reviewers ask this on about half of all refactors.
- Is the behavior really unchanged? Removed checks, reordered side effects, and changed error paths are where refactors break things. Reviewers flag unannounced behavior changes in refactors about five times as often as in other PR types.
- Will it be slower?
- Can it be rolled back safely?

## Background

How the code is organized today: the modules involved, what each does, and who depends on them.

## Problem Summary

The concrete problem the refactor removes (duplicated logic, unclear ownership, an extension it blocks, a class of bugs it prevents) and the new structure, in one sentence. "Improve code quality" is not a reason.

## Details

- **Moves vs. logic changes** (required): which parts are pure moves or renames, and which change logic. For a large refactor, point to the commits or files that are pure moves, so reviewers can skim them. Don't list every file. When Details opens with a Change map, mark its parts as moves or logic changes there, and use this field for what the map doesn't say, such as how you checked that the moves change nothing.
- **Behavior change** (required): `None intended`, and how that was checked; or each intentional change, including removed checks and changed error messages.
- **Compatibility** (required): external interfaces, SQL, configs, metadata and the EditLog, storage formats, Thrift and Protobuf structures, log and metric names. `None changed` is a valid answer.
- **Performance impact** (required): `None expected` and why, or measured numbers when the code is on a hot path.
- **Rollback** (required): how to roll back if a problem shows up after merge, and the risk. Say whether a plain revert is safe: it is not if the refactor changed anything that is persisted or sent between processes.

## Testing

The existing tests that cover the refactored code, by name, and any tests added where coverage was thin. For a large rewrite, describe the differential or golden comparison between the old and new code.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- Pure moves and renames in their own commits, apart from logic changes, so that Moves vs. logic changes can point reviewers to them.
- How "no behavior change" was checked: the existing tests by name, and a comparison of old and new results where coverage is thin.
- Numbers for code on a hot path.
- Whether anything persisted or sent between processes changes; it decides whether a plain revert is safe.
