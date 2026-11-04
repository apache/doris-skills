# Rewrite mode

Rewrite mode rewrites any PR's description for comparison or evaluation. It never touches GitHub, never stops to ask, and ends with the report of step 6 (`references/check-and-publish.md`). Read this file before collecting the facts; where it differs from the other files, it wins.

## The facts

Use the final diff, the commits, the linked issues, the original description, and the code, but not the review discussion (review comments, replies, labels added later) unless the user asks. The point is to see what this standard produces from the author's own material, without answers borrowed from reviewers. Commit messages are the author's material, including those written in reply to a review.

- **Describe the PR as of its final head.** For a merged PR, later changes on `master`, such as a changed default or a follow-up fix, go in the final report, not in the description.
- **Related PRs.** List the related PRs that the material names or git history shows: the PRs that the final diff builds on, even if they were opened later (a long-open PR is often rebased onto them), and the same change on other branches. Leave out later PRs that don't bear on this diff, such as follow-ups. Don't search GitHub for other PRs on the same problem.
- **Check the original description.** When the PR was rebased or reworked, compare each claim in the original description with the final diff. Leave out claims that no longer hold, and list them in the final report.

## Record instead of stopping

Where the other modes stop and ask (`references/stop-and-ask.md`), Rewrite mode records what it finds:

- A required fact you cannot derive becomes `TODO(author): <what is missing>` in its field, and a missing Feature issue becomes a TODO on `Issue Number`.
- A problem you found goes in the field that asks about it: Other paths and branches, Compatibility, Security and privileges, or Testing for an existing test that the diff leaves asserting the old behavior. State it with its evidence if you verified it in the code, tests, or configs; if you could not, write `TODO(author): confirm <the problem and its evidence>`. A problem that no field asks about goes only in the final report.

Put each TODO at the end of its field. The final report lists every TODO, with the `confirm` TODOs apart from the missing facts, so that readers can tell what the author left out from what you found.

## The drafts

Also save the original title and description as `pr-<number>.orig.md`, beside the draft and in the same format, for side-by-side review. A Feature without an issue gets the TODO on `Issue Number` and no issue draft.

## Pre-submission status

Judge it from the evidence you can trace: when the author's verification is unknown, it is `Partially verified` with the gap named, never `Ready`.

## AI Disclosure

You generated the description; for the code, use only explicit evidence: a trailer that names a tool or model (`Co-authored-by: Claude Sonnet 5.5 <noreply@anthropic.com>`, `Claude-Session:`), or a statement or a "Generated with" line in the original description. A co-author trailer that names no tool or model is not evidence of AI use, and neither is a branch name. A trailer covers the commit it is on; when other commits hold most of the final diff, say so. Leave out session links, which are private. For example:

```markdown
- Tool: Claude Code (Claude Opus 5.5) for this description; Claude Sonnet 5.5 for the code, per the commit's `Co-authored-by` trailer
- Generated: this description; the code and tests, co-authored (which parts is not stated)
- Human review: not stated
```

Omit the Prompts line unless the original description includes the prompts.
