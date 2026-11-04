# Tests and CI: protect the power to detect failures

Check the failure-detection chain: test selection → input or fixture → the actual call → assertions → exit code → summary status. Look for false passes: zero tests, everything skipped, loops over empty collections, swallowed exceptions, mocks that replace the logic under test, failures filtered out, and the like.

When a change may alter what a check can detect, keep one real passing sample and one known failing sample. Confirm that the pass still passes and the failure is still caught. If the fix is for a false alarm, show why the original alarm was wrong, and keep detecting the real errors.

When changing a flaky test, explain the mechanism behind the instability and control that condition. As evidence of stability, use the failure rates before and after the change over the same number of runs, or a deterministic reproduction that forces the timing. Add a timeout or a wait only when it matches a real timing contract and there is evidence for it; deleting assertions, skipping without a reason, or rerunning endlessly is no substitute for a fix.
