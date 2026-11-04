---
name: develop-with-evidence
description: Improve completeness, correctness, and trustworthiness throughout coding and before a pull request. Use for feature/API implementation, bug fixes, refactoring, performance optimization, frontend work, test/CI changes, dependency/configuration updates, migrations, or checking an existing patch. Select proportional verification, test the tests when warranted, and connect final claims to the actual code. Leaves an English handoff file (a PR description draft plus the facts and evidence behind it, which the PR step takes as given). Trustworthy development and a pre-PR self-review: the main agent makes every judgment, code change, and conclusion, and may hand evidence gathering to subagents; work after the PR is published is out of scope.
---

# Developing with evidence

Make the goal, the implementation, the verification, and the final description of a change agree with one another. Build evidence around actual behavior, and verify in proportion: each check should settle a specific uncertainty.

## Boundaries

- Use this skill from the moment you start to understand the task until the local implementation, verification, self-review, and delivery notes are done. When you take over an existing patch, fill in the key evidence it lacks.
- The main agent makes every judgment, every code change, and the final conclusions. When the environment offers subagents, evidence gathering that reads a lot and comes back with checkable conclusions can go to them, to keep the main session's context small; see [subagents.md](references/subagents.md). Don't run a cross-model review or bring in external reviewers on this skill's account, and call the self-review at each stage what it is: a self-review.
- Publishing the PR, following CI and answering reviews after it is published, watching the change after it merges, and recurring tasks are outside this skill. At delivery, write the handoff file, with a PR description draft and the facts behind it, for the PR step to use; it is no trigger to publish, merge, or deploy anything automatically.
- Follow the user's requests, the project's conventions, and the authorizations already given. When the scope is clear, keep going; don't add approvals for routine steps. Ask a specific question only when a behavioral contract, a compatibility question, or an irreversible trade-off truly cannot be settled from the information at hand, and first finish the work that can proceed without the answer.
- When fixing a bug, confirm that the defect is real before changing code, as stage 1 describes. When the defect is proven not to exist, or it can neither be reproduced nor traced through a causal chain, stop developing, explain the evidence, and ask the developer how to proceed. This holds even when you find out in a later stage.
- Keep the developer's existing changes: don't reset the working tree, don't slip in unrelated cleanup, and don't run unauthorized migrations on real data. Don't widen the change just to gather evidence.

## Reading this skill

Paths are relative to this skill's directory. Read a stage's file when you enter that stage, and don't read later stages ahead of time; each stage file says when to read the other reference files. Don't reread a file that this session has read and that is still in context; after the context has been compacted, read it again when you need it.

| Stage | Output | Read on entry |
|---|---|---|
| 1. Define the goal, the scope, and how much to verify | Evidence that the defect exists (for a bug), the contract and the acceptance results, the PR type, the verification strategy, the handoff file | [1-scope.md](references/stages/1-scope.md) |
| 2. Understand the mechanism, then implement what is needed | The causal chain or the target contract, and the implementation that answers it | [2-implement.md](references/stages/2-implement.md) |
| 3. Run verification that tells right from wrong | Evidence that tells right from wrong | [3-verify.md](references/stages/3-verify.md) |
| 4. Self-review the current code once, with a purpose | Self-review conclusions and fixes | [4-self-review.md](references/stages/4-self-review.md) |
| 5. Keep the evidence tied to the final candidate | Evidence that matches the final code | [5-evidence.md](references/stages/5-evidence.md) |
| 6. Wrap up and deliver a result that can be trusted | The final handoff file, the pre-submission status, a summary for the user | [6-deliver.md](references/stages/6-deliver.md) |

When an observation overturns the original hypothesis, go back to stage 2; when you change code after the self-review, re-verify by stage 5. When resuming after an interruption, first read the handoff file itself and [5-evidence.md](references/stages/5-evidence.md), then continue from the progress the handoff file records.

The sources of these engineering principles are in [sources.md](references/sources.md); you don't need them to follow the workflow.
