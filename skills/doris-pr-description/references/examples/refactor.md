# Refactor: example

Illustrative: the PR numbers, class names, and figures are made up.

````markdown
Title: [refactor](fe) Share HMS partition pruning between the Hive and Hudi connectors

### Background

Doris reads Hive and Hudi tables through two FE connectors, and both kinds of table keep their partitions in a Hive Metastore (HMS). When planning a query, each connector prunes partitions itself: it evaluates the query's predicates against the HMS partition values before listing files. The HMS client that both connectors use lives in `fe-connector-metastore-hms`.

### What problem does this PR solve?

Issue Number: None
Related PR: #58530 (a NULL partition fix that had to be made in both connectors)
PR Type: Refactor

Problem Summary:

The Hive and Hudi connectors each carry their own copy of the HMS partition pruning logic, about 500 lines apiece. Fixes keep landing in one copy and not the other; #58530 had to be made twice. This PR moves the shared logic into `HmsPartitionPruner` in `fe-connector-metastore-hms` and keeps only format-specific value parsing in each connector.

### Details

- **Moves vs. logic changes:** The first commit only moves the Hive copy into `HmsPartitionPruner`. The second deletes the Hudi copy and routes Hudi through the shared class; review that commit closely.
- **Behavior change:** None intended. The two copies differed in one place: Hudi skipped partitions whose value failed to parse, while Hive raised an error. The shared code keeps each connector's behavior through a flag. Pruned partition lists for all queries in `external_table_p0/hive` and `external_table_p2/hudi` were compared before and after and are identical.
- **Compatibility:** None changed. No configs, metadata, or Thrift structures are touched.
- **Performance impact:** None expected, since the algorithm is unchanged. Planning time for a Hive table with 50,000 partitions stayed at about 1.2 s (median of 10 runs).
- **Rollback:** A plain revert is safe; nothing is persisted or sent to BE.

### Testing

- `HiveConnectorMetadataPartitionPruningTest` and `HudiPartitionPruningTest` pass and now exercise the shared class.
- Existing suites `external_table_p0/hive` and `external_table_p2/hudi` pass.
- The pruned partition comparison described under Behavior change used a temporary log line that is not part of this PR.

### Notes for Reviewers

- `HmsPartitionPruner.evaluate()` drops a null check on the partition range that only the Hudi copy had: ranges have been non-null since #57001.

### Release note

None

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: No
- Pre-submission status: Ready

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: the second commit and this description
- Human review: The author reviewed the second commit line by line.
````
