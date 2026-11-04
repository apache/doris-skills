# Bugfix: establish a reproducible causal chain

1. Record the input, the initial state, the order of operations, and the expected and actual results. Check whether an existing fix already covers the problem.
2. Prefer reproducing it on the real call path; when the case needs to shrink, keep the key conditions that cause the defect.
3. For a defect that can be reproduced at a reasonable cost, run the same regression test on both sides: the baseline must fail because of the target defect, and the fix must pass. A build failure, a missing dependency, or no tests collected is not a valid "red".
4. Find the existing tests closest to the defect, one layer each for unit tests and end-to-end tests, and explain why they missed it: no case for the trigger condition, the faulty component mocked out, a check only for success or for row counts, running as a privileged user, and so on. The new test must close that gap.
5. If the original environment cannot be had, use the closest substitute and state the gap. Keep the items still to verify, and don't claim that the check in both directions (fails before, passes after) is complete.
6. For a concurrency or intermittent problem, prefer controlled scheduling, barriers, fixed inputs, or a fixed order of events. State the number of random repetitions and the environment, and don't read "not reproduced yet" as "doesn't exist".

Don't insist on broad mutation testing for every defect. Only when you suspect that the assertions are hollow, the path isn't reached, or the test would still pass with the fix reverted, pick one minimal counterexample to check.
