# doriscli contract

These skills are written directly against **`doriscli`** (the Apache Doris CLI, shipped
in the companion `doris-cli` repository). The runtime-diagnosis logic in
`doris-best-practices` hard-codes the command names and JSON field names below.

**If doriscli renames a command or output field, update both repositories together.**
There is no render/adapter layer to absorb the change, and a renamed field silently
degrades to `null` in the agent's reasoning instead of raising an error.

doriscli is **optional**: when it is not installed the skills fall back to the
MySQL-protocol + FE HTTP path (see
`skills/doris-best-practices/references/cli-investigation.md` → "Native SQL + HTTP
path"). The commands and fields here are what the skills rely on when doriscli *is*
present.

## Commands

| Command | Used for |
|---|---|
| `doriscli sql "<q>"` (`--profile`, `--no-cache`, `--set k=v`, `-f file`) | run SQL / `EXPLAIN` / `SHOW CREATE TABLE`; profiled execution |
| `doriscli profile get <qid>` (`--full`, `--raw`, `-f file`) | fetch + parse one profile |
| `doriscli profile list` (`--active`, `--limit N`) | recent / currently-running queries |
| `doriscli profile diff <slow> <fast>` | operator-level regression |
| `doriscli profile history "<pat>"` (`--days N`, `--limit N`) | p50/p99 trend from `audit_log` |
| `doriscli tablet <db.t>` (`--detail`, `--partition p`) | model / bucket / sort key + tablet health |
| `doriscli auth status` | MySQL + HTTP connectivity, backends, version |
| `doriscli use <name>` | switch the active environment |
| global `--format json`, `--env`, `--socks5`, `--init-sql` | machine-readable output / routing |

## JSON fields

**`profile get`**
- `summary.total_time_ms`
- `query_stats.{total_scan_rows, spilled_operators, blocked_operators}`
- `time_breakdown.plan`
- `operators[].{selectivity, spilled, shuffle_bytes, join_type, peak_mem_bytes, blocked_on_upstream, cache_hit_pct, runtime_filters}`
- `scanned_tables.<table>.{ddl, tablet_skew, total_rows}` (object keyed by table name)
- `served_by`, `fetch_attempts` (present on fetch failure)

**`tablet`**
- `model`, `bucket_key`, `bucket_count`, `sort_key`, `total_rows`
- `health.tablet_skew`
- `columns[].ndv` (column cardinality — inlined, so a separate `SHOW COLUMN STATS` is usually unnecessary)

**`auth status`**
- `mysql_status`, `http_status`, `http_probe`
- `backends[].alive` (empty / all-not-alive ⇒ compute suspended or unavailable)
