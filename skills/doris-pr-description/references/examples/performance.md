# Performance: example

Illustrative: the PR numbers, names, and figures are made up.

````markdown
Title: [opt](be) Use a bitmap for IN predicates on dense integer constants

### Background

The BE evaluates an `IN` predicate with constant values during the scan. When the predicate is prepared, its constants go into a hash set (`HybridSetBase`), and the value of every scanned row is then hashed and looked up in that set.

### What problem does this PR solve?

Issue Number: None
Related PR: None
PR Type: Performance

Problem Summary:

Dashboards often filter with long `IN` lists of small integer codes, such as `status_code IN (...)` with 500 values. On a 1-billion-row table, such a scan takes 4.1 s, most of it spent probing a hash set. This PR tests membership with a bitmap when the constants are integers in a narrow range, which brings the scan to 1.5 s.

### Details

- **Why it was slow:** Each row is hashed and probed in the `IN` predicate's `HybridSetBase` hash set. A CPU profile of the query below attributes 61% of scan time to the probe.
- **Optimization:** When all constants are integers and `max - min` is below 65,536, build a bitmap of `max - min + 1` bits when the predicate is prepared, and test `bitmap[v - min]`, after a range check on `[min, max]`. Other `IN` predicates keep the hash set.
- **Results:** `SELECT count(*) FROM events WHERE <column> IN (<500 constants>)` over 1 billion rows, 3 BEs with 16 cores and 64 GB each, median of 5 runs.

  | Column type and constants | Before | After |
  |---|---:|---:|
  | `INT`, 500 values within a range of 2,000 | 4.1 s | 1.5 s |
  | `SMALLINT`, 500 values within a range of 2,000 | 3.9 s | 1.4 s |
  | `INT`, 500 values within a range of 10 million (fallback) | 4.0 s | 4.0 s |

- **Applicability and cost:** Integer types only, with at least 16 constants within a range below 65,536; everything else falls back to the hash set. The bitmap costs at most 8 KB per predicate instance. About 120 lines in `vin_predicate`, with no new config.

### Testing

- Existing suites under `query_p0` that use `IN` predicates pass.
- New BE unit test for the bitmap: the range edges, values outside the range, negative values, NULLs, and the fallback decision.
- New regression test `query_p0/in_predicate/test_in_bitmap.groovy`: compares results with the fallback forced through a debug point.

### Release note

Speed up `IN` predicates with many integer constants that fall within a narrow range.

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: No
- Pre-submission status: Ready

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: the unit test and this description
- Human review: The author wrote the predicate change and reviewed the generated test.
````
