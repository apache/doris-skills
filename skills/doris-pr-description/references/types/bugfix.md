# Bugfix

Title tag: `fix`. Use when the old behavior was a defect: wrong results, crashes, unexpected errors, leaks, hangs, or behavior that contradicts the documentation. If the old behavior worked as designed and the PR makes it better, use Enhancement.

## What reviewers check

- Is the problem real, and is the root cause right, or does the change only hide the symptom?
- Would the new test still pass with the fix reverted?
- Do other code paths, file formats, or release branches have the same bug?

## Background

How the affected feature works when it works: the mechanism the bug sits in, and the terms the rest of the description uses. In the example below, how an Iceberg table's partition spec can change and how each data file records the spec it was written with.

## Problem Summary

The symptom as a user or developer sees it (the wrong result, the error text, where it crashes), who runs into it, and the fix in one sentence.

## Details

- **Frequency** (required): `Always`, `Intermittent`, or `Not observed`, followed by the trigger: the conditions, or the shortest reproduction. For an intermittent bug, give the rate if it is known (`about 1 in 20 P0 runs`). For a bug found by reading code, say so: `Not observed; found by code review. Triggers when ...`. When the trigger depends on an external system, describe the behavior that triggers it (`REST catalogs that answer a table lookup for a view with HTTP 400`) and name the systems known to do that; not knowing which systems do is not a missing fact.
- **Root cause** (required): which code is wrong, and why it produces the symptom. Name the function or class, in one to three sentences.
- **Why existing tests missed it** (required): cover both layers, the unit tests and the end-to-end regression suites under `regression-test/suites/`. For each layer, name the closest tests, say what they check, and give the gap that let the bug through; if no test at a layer reaches the faulty code, say so. `references/facts/existing-tests.md` shows how to find the tests and check that CI runs them. Common gaps:
  - No case for the trigger condition.
  - A mocked component, such as a privilege check stubbed to always pass.
  - A check on row counts, or on success alone, instead of on values.
  - A regression case that runs as `root`, so privilege checks always pass.
  - A case that the PR pipelines skip: because of its groups, an exclude list, or a run option such as `excludeDockerTest` or `-runNonConcurrent false`.
  - A test that asserts the buggy behavior, in an assertion or in a generated `.out` file. It fails once the fix lands, so say whether this PR updates it.

  This tells reviewers whether the new test closes the gap.
- **Fix** (required): the approach and its scope, and why the fix sits at this layer if a reviewer could expect another. Don't list files.
- **Other paths and branches** (required): the paths that share the faulty pattern, such as the same logic for other file formats, catalogs, data types, cloud and shared-nothing modes, or FE and BE. Mark each as fixed here, not affected (and why), or still to fix (and where that is tracked). Then name the release branches that have the bug and the PR that introduced it, if known; committers use this to choose where to cherry-pick. If the fix depends on another PR, name the branches that lack it, since a cherry-pick needs it too. `references/facts/bugfix-origin.md` shows how to check a release branch; say which branches you could not check.
- **Configs and defaults** (when the fix adds or changes a config or session variable, such as a switch that turns the fix on): the name, the default, whether it can change at runtime, and what users get while it is off.

## Testing

Name the test that fails before the fix and passes after it, and what the failure looked like (`returns NULL for dt`, `BE crashes in ...`). Run it against the unfixed code when you can; if you could not, say so instead of claiming it. If no automated test is feasible, explain why, and give the manual reproduction and its result.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- The trigger, and a test that fails on the code before the fix and passes with it, with the failure it showed. A build error, or a test that never ran, is not a failure.
- The closest existing unit tests and regression suites, and why each missed the bug. Write the new test to close that gap: if the closest suites run as `root`, the new one connects as a user without the privilege; if they check only row counts, it checks values.
- That a PR pipeline runs the new test: its groups, the exclude lists, `docker(...)`, and `nonConcurrent`, as `references/facts/existing-tests.md` describes. If none does, move it, or record why not.
- The other paths that share the faulty pattern, and which of them this PR fixes.
- The PR that introduced the bug and the release branches that have it, by `references/facts/bugfix-origin.md`, naming any branch that could not be checked.
