# Revert: example

Illustrative: the PR numbers, test names, and results are made up.

````markdown
Title: Revert "[opt](be) Use a bitmap for IN predicates on dense integer constants"

### Background

#59120 sped up `IN` predicates on integer columns: when the constants fall within a narrow range, it tests membership with a bitmap indexed by `v - min` instead of a hash set.

### What problem does this PR solve?

Issue Number: None
Related PR: #59120 (reverted)
PR Type: Revert

Problem Summary:

#59120 returns wrong results for `BIGINT` columns: when a value lies far below the smallest constant, `v - min` overflows and the range check passes, so rows outside the `IN` list are returned. `query_p0/in_predicate/test_in_bigint_range` has failed in every P0 run since the merge.

### Details

- **Why not fix forward:** The overflow affects the range check in three places, and the fix needs its own review and benchmark; P0 is blocked for every PR in the meantime.
- **Original author notified:** Yes; the author agreed to the revert in #59120.
- **Follow-up:** The author will re-land the optimization with the overflow fix, tracked in #59188.

### Testing

- `test_in_bigint_range` passes locally with this revert; P0 will confirm.

### Release note

None

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: No
- Pre-submission status: Ready

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: this description
- Human review: The author checked the description.
````
