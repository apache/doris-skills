# 6. Wrap up and deliver a result that can be trusted

Before finishing, answer the questions below; expand only the ones that apply to this task:

| Question | Evidence needed |
|---|---|
| Is the problem or the goal clear? | An explicit contract; for a bug, a reproduction or the stated limits of the reproduction |
| Is the implementation complete? | The root cause or the design rationale, the related call paths, and the integration points |
| Can the tests tell right from wrong? | Assertions on the behavior; a counterexample or a targeted revert where needed |
| Are compatibility and boundaries handled? | Evidence on the inputs, configs, errors, and states that this change's risks involve |
| Do the results match the current code? | The current diff or version, the right build, and reruns of the affected checks |
| Can the final description be trusted? | It matches the actual change and names what is unverified and the trade-offs |

Stop optional verification once the key promises have enough evidence, the substantive problems found have been dealt with, and the project's required checks are done or their blockers are stated accurately. Before adding a check, say which specific uncertainty it settles; without a specific question, don't widen the testing.

## Pre-submission status

- **`Ready`:** the change's key promises have current evidence, the project's applicable required checks are done, the known substantive problems are resolved, and the description matches the final diff. It is a delivery judgment within a limited scope, not a proof that there are no defects.
- **`Partially verified`:** the change is ready to be examined, but a needed verification is blocked by the environment, has not run yet, or has gone stale; list the gaps. Don't write "all passed" or "safe to merge".
- **`Not ready`:** there is a confirmed substantive error or a contract conflict that was not accepted, or a related required check still fails. Keep fixing what can be fixed, and state accurately what cannot. Such a PR can be opened only as a Draft.

These statuses exist for honest delivery. They create no extra authorization or approval process, and they don't override the user's instructions for other tasks. The pre-submission status goes into the PR description, so that reviewers can compare the author's verification before submission with what CI and review find. Write the names exactly as above in the handoff file and the PR description, and follow `Partially verified` and `Not ready` with the gap or the reason, such as `Partially verified: not run against a Glue catalog`. Update the status whenever it changes.

## Delivery

Finally, complete the handoff file by `references/handoff.md`. In your reply, in the user's language, summarize the problem or the goal, the actual change, the key verification, the limitations, and the pre-submission status, and give the path of the handoff file. For a light task, a few sentences are enough. Don't claim "zero defects" or "every scenario covered", and don't let test counts or your own confidence stand in for evidence. The developer should be able to tell `Ready`, `Partially verified`, and `Not ready` apart.
