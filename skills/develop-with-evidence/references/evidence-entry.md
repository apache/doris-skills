# Evidence entries

Use this format to help both the work and the communication about it. For a light task, a few lines are enough; keep a fuller record only for complex tasks.

## A useful evidence entry

The handoff file is in English, and its entries use these labels:

```text
Claim:        the behavior, performance, or compatibility promise to prove
Code:         the baseline and candidate versions (commits); with uncommitted changes, the diff and the state of the relevant files
Environment:  the build, dependency, config, input, and resource conditions that actually affect the conclusion
Method:       the command actually run, the steps taken, or the place checked
Expected:     the expected result, from the requirement, the contract, or an independent reference
Observed:     the actual result, the exit code, and where the necessary log lines are
Status:       VERIFIED / FAILED / NOT_RUN / NOT_APPLICABLE
Scope:        what this proves, and what it does not
```

- `VERIFIED`: the target of this entry has enough evidence that matches the current candidate. Say whether it comes from an execution, a static check, or a UI observation; one kind never stands in for another.
- `FAILED`: it ran, but the result is not what was expected. Tell a product defect, a test problem, and an environment failure apart, and keep the evidence.
- `NOT_RUN`: it did not run, could not be completed, or its evidence has gone stale. State why and what that affects; it never counts as a pass.
- `NOT_APPLICABLE`: the check has nothing to do with the current behavior; give the reason briefly. Never use it to hide a check that was hard to do.

Even when a command exits with zero, check that the target tests really ran, the right input was loaded, and the target path was reached, and that nothing was skipped wholesale, returned zero results, or swallowed an error.

Committed code can be identified by its commit; uncommitted changes need the diff, the contents of the relevant files, or a temporary snapshot. `HEAD` alone does not describe a dirty working tree.

## The minimum delivery when blocked

Keep doing the implementation and the checks that don't depend on the blocker, and state:

```text
Done:          the scope of the change, and the evidence so far
Not verified:  the specific target or path, not a vague "testing isn't finished"
Reason:        the missing environment, access, or dependency, or the contract still to be settled
Impact:        which conclusions cannot hold for now
Next step:     a check that can be run as it is, or the specific trade-off the developer must decide
```

In the handoff file, these become `NOT_RUN` evidence entries and the gaps named in the pre-submission status.

Don't change production semantics, loosen assertions, or mark a required check as passed because an environment is missing. A developer accepting a limitation doesn't change the fact that it is unverified.
