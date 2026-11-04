# Feature: example

Illustrative: the PR and issue numbers, names, and results are made up.

````markdown
Title: [feature](iceberg) Support reading row lineage columns of Iceberg v3 tables

### Background

Iceberg v3 adds row lineage: every row carries a `_row_id` that stays the same across updates, and a `_last_updated_sequence_number` that names the commit that last changed the row. Engines expose both as hidden metadata columns, which `SELECT *` leaves out. Doris already reads v3 tables, including their deletion vectors (#58720), but not these two columns.

### What problem does this PR solve?

Issue Number: close #59001
Related PR: #58720 (Iceberg v3 deletion vectors, which this builds on)
PR Type: Feature

Problem Summary:

Users who build incremental pipelines on the row lineage columns cannot read them from Doris and fall back to Spark. This PR exposes both as hidden columns of Iceberg v3 tables. Rows that were never rewritten don't store the values; the spec has readers derive them from the data file's first row ID and data sequence number, and that derivation in the BE scan is most of the code. Queries that don't select the columns are unaffected.

### Details

- **Change map:** +840 −30 in 22 files, of which tests are +520: a regression suite +390, 150 of them its generated `.out`, and FE unit tests +130. The production code is +320 −30, in three parts:
  1. Deriving the values that a data file doesn't store, from its first row ID plus each row's position and from its data sequence number (+180 −20 in the BE's `IcebergTableReader`). Read it first.
  2. Exposing the two hidden columns on v3 tables, which `show_hidden_columns` reveals (+80 −10 in `IcebergExternalTable`).
  3. Passing each data file's first row ID and data sequence number to the scan (+40 in `IcebergScanNode`, and +20 for two optional fields in `TIcebergFileDesc`).
- **Scope:** Read-only, for v3 tables in Iceberg catalogs (REST, HMS, and Glue). Writing row lineage is out of scope. On v1 and v2 tables the columns don't exist, and selecting them fails with `Unknown column`.
- **Design:** Hidden columns, as defined by the Iceberg v3 spec and as Spark and Trino expose them, so that queries move between engines unchanged. A table function such as `iceberg_row_lineage(tbl)` was considered and rejected, because predicates on its output cannot be pushed down into the scan. Proposed in #59001, opened with this PR; not discussed yet.
- **Usage:**

  ```sql
  SELECT _row_id, _last_updated_sequence_number, id, name
  FROM iceberg_catalog.db.users
  WHERE _last_updated_sequence_number > 120;
  ```

- **Default behavior:** Always available on v3 tables. The columns are hidden: `SELECT *` and `DESC` leave them out unless `show_hidden_columns` is set to `true`.
- **Compatibility:** Queries that select the new columns need upgraded BEs; during a rolling upgrade, an old BE rejects them with an error instead of returning wrong values. Other queries are unaffected. Nothing changes in metadata or the image, so downgrading is safe.
- **Follow-up plan:** Write support is tracked in #59002.

### Testing

- New regression suite `external_table_p0/iceberg/test_iceberg_v3_row_lineage.groovy`: reads both columns from v3 tables written by Spark, including after updates and after deletes with deletion vectors; filters and joins on `_row_id`; and checks the error when selecting the columns from a v2 table. Run locally with REST and HMS catalogs against the Iceberg docker environment.
- New FE unit test for resolving hidden columns with `show_hidden_columns` on and off.

### Release note

Support reading the row lineage columns `_row_id` and `_last_updated_sequence_number` of Iceberg v3 tables.

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: Yes (apache/doris-website#2401)
- Pre-submission status: Partially verified: not run against a Glue catalog, which needs AWS credentials

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: the FE planning code, the regression suite, and this description
- Human review: The author reviewed the FE changes line by line and checked the regression suite for coverage.
- Prompts:
  1. Expose `_row_id` and `_last_updated_sequence_number` of Iceberg v3 tables as hidden columns.
  2. Drop the new session variable from the first version and reuse `show_hidden_columns`.
  3. Add negative cases for v2 tables.
````
