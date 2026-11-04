# Release/Dependency: example

Illustrative: the version, the upstream fix, and the PR numbers are made up.

````markdown
Title: [deps](thirdparty) Upgrade Apache Arrow from 24.0.0 to 24.0.1

### Background

Apache Arrow is built from source under `thirdparty/` and linked into the BE. The BE uses Arrow's Parquet writer for `SELECT ... INTO OUTFILE`, and the Arrow format for Arrow Flight SQL results.

### What problem does this PR solve?

Issue Number: close #59310
Related PR: None
PR Type: Release/Dependency

Problem Summary:

Parquet files written by `SELECT ... INTO OUTFILE` carry wrong min/max statistics for `DECIMAL` columns, so engines that prune row groups by statistics skip data they should read (#59310). The bug is in Arrow's Parquet writer and is fixed upstream in 24.0.1.

### Details

- **Versions:** `arrow` 24.0.0 → 24.0.1, from the GitHub release tarball; `ARROW_MD5SUM` updated in `thirdparty/vars.sh`.
- **Upstream changes:** The `DECIMAL` statistics fix, plus two other Parquet writer fixes listed in the 24.0.1 release notes (https://arrow.apache.org/release/). The license is unchanged (Apache-2.0), and a patch release keeps the ABI.
- **Compatibility:** Built with the standard toolchain on Linux x86_64 and ARM64 and on macOS ARM64. Files written with 24.0.1 are standard Parquet that older readers handle.
- **Rollback:** Revert this PR and rebuild the third-party libraries. Files written in the meantime stay readable.

### Testing

- Third-party build, BE build, BE unit tests, and P0 on Linux x86_64 and ARM64.
- New regression test in `export_p0/outfile/parquet`: exports `DECIMAL` columns and reads them back from Spark with a predicate that relies on row-group statistics.
- Prebuilt third-party packages regenerated in apache/doris-thirdparty#312.

### Release note

Fix wrong `DECIMAL` statistics in Parquet files written by `OUTFILE` and `EXPORT`, by upgrading Apache Arrow to 24.0.1.

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: No
- Pre-submission status: Ready

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: this description
- Human review: The author checked the description.
````
