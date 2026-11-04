# Bugfix: example

Illustrative: the PR numbers, names, and results are made up.

````markdown
Title: [fix](iceberg) Fix NULL partition values after partition spec evolution

### Background

An Iceberg table's partition spec says how rows map to partitions, and it can evolve: a newer spec may add, drop, or replace partition fields. Each data file keeps the ID of the spec it was written with (`specId`) and stores its partition values in that spec's field order. When Doris plans a scan, the FE's Iceberg connector reads each file's partition values from the table metadata.

### What problem does this PR solve?

Issue Number: close #58123
Related PR: #57210 (introduced the bug)
PR Type: Bugfix

Problem Summary:

After an Iceberg table's partition spec replaces `identity(dt)` with `day(ts)`, Doris returns NULL for `dt` in rows from files written under the old spec, while Spark returns the right values. This PR reads each file's partition values with the spec that the file was written with.

### Details

- **Frequency:** Always, on Iceberg tables whose partition spec has replaced a field and that still hold files written under the old spec.
- **Root cause:** Since #57210, the Iceberg connector reads every file's partition tuple by position using the table's current spec (`table.spec()`). A file written under spec 0 carries spec 0's tuple, so `dt` maps to a field that no longer exists and becomes NULL.
- **Why existing tests missed it:** Unit tests: `IcebergPartitionValueAdapterTest` builds its files from a single spec, so no file is ever read with a newer one. Regression: the spec evolution suites in `external_table_p0/iceberg`, such as `test_iceberg_partition_evolution`, only add partition fields. Added fields keep the old positions, so the current spec still matches the old files.
- **Fix:** Look up the spec by each file's `specId` instead of using the current spec. The change stays in the connector's partition value parsing.
- **Other paths and branches:** Paimon and Hudi read partition values from file metadata and are not affected. `branch-4.1` has the bug, since #57210 was cherry-picked there; `branch-4.0` does not.

### Testing

- New regression test `external_table_p0/iceberg/test_iceberg_spec_evolution_replace.groovy`: returns NULL for `dt` on master without the fix and the right values with it. Run locally against the Iceberg docker environment.

### Release note

Fix NULL partition values when querying Iceberg tables whose partition spec has replaced a partition field.

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: No
- Pre-submission status: Ready

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: the fix, the regression test, and this description
- Human review: The author read the fix and ran the regression test locally.
- Prompts: Asked the agent to find why `dt` is NULL in the reproduction from #58123, then to fix it in the connector's partition parsing rather than in the BE scanner, and to add a regression case that replaces a partition field.
````
