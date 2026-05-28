---
title: CLI-Based Query Investigation
tags: [cli, investigation, diagnostics, profiling, slow-query]
---

## CLI-Based Query Investigation

Evidence-first runtime diagnosis using {{CLI}}. Collect profile, tablet, DDL, stats, EXPLAIN, or connection evidence before forming hypotheses. Do not jump to schema fixes.

---

### Binary Policy

- Primary command: `{{CLI}}`
- Detection order:
  1. `{{CLI_PATH_ENV}}` environment variable → use that binary path
  2. `command -v {{CLI}}` → use from PATH
  3. If none available: use fallback SQL (see end of this document)

### Safety Policy

- **Read-only evidence collection** may run proactively: `profile get`, `profile list`, `profile diff`, `profile history`, `tablet`, `auth status`, `SHOW CREATE TABLE`, `EXPLAIN`
- **Before executing user SQL with `--profile`**: check whether the SQL is safe (no DDL, no mutation, no unbounded scan without LIMIT). For unknown or potentially expensive SQL, run `EXPLAIN` first and ask the user to confirm or request an existing `query_id` instead
- **Never run** DDL, data mutations, cluster changes, or Cloud operations as part of diagnosis without explicit user confirmation
- Always use `--format json` for agent-readable output

### Evidence-First Hard Gate

- Do not present root causes, DDL rewrites, materialized views, index changes, bucket changes, or tuning recommendations until at least one evidence source has been collected or attempted
- Valid evidence sources: `profile get`, `profile diff`, `profile history`, `profile list --active`, `tablet`, `{{CLI}} sql "EXPLAIN ..."`, fallback SQL output, `auth status`, or an explicit user-provided profile/tablet/EXPLAIN snippet
- If a command cannot be executed locally because `{{CLI}}` or credentials are unavailable, say that evidence could not be collected here, then provide the exact commands for the user to run. Do not stop at "install {{CLI}}"
- If no evidence is available yet, the correct response is a short investigation plan plus the first read-only command to run, not a diagnosis
- After collecting evidence, report findings as hypotheses with confidence and caveats, not as guaranteed root causes

**Output ban when no evidence has been collected or attempted:** Do not include sections named or containing: "Likely causes", "Root cause", "Recommended fixes", "Quick wins", "Optimization plan", CREATE TABLE, CREATE MATERIALIZED VIEW, ALTER TABLE, SET session variables, or any tuning parameter recommendations. The only permitted output before evidence is: (1) investigation plan listing the commands to run, (2) the commands themselves, (3) a request for the user to provide output or confirm execution. Hypotheses are allowed only after at least one evidence command has returned output or the user has provided equivalent data.

### Connection-First Rule

If the user reports that `{{CLI}} sql`, `{{CLI}} profile get`, or any CLI command **fails, times out, or returns an error**, treat it as a connection-layer problem first, not a query performance problem. The first command must be `{{CLI}} auth status --format json`. Do not suggest query timeout changes, session variables, DDL, or performance tuning until connectivity (mysql_status, http_status) is confirmed working. If the cluster is Cloud-managed, also check `{{CLI}} cloud cluster get --format json` (cluster may be Suspended).

---

### Evidence Collection Workflows

**Prefer existing profiles over re-executing SQL.** Real support workflows usually start with a query_id, a complaint about a known slow query, or output from monitoring. Re-executing expensive SQL wastes resources and may not reproduce the original conditions.

#### Investigation ladder

Use the most specific available path:

1. User provides `query_id` → `profile get`
2. User provides slow-vs-fast query IDs → `profile diff`
3. User says query is running → `profile list --active`
4. User provides SQL but no `query_id` → `profile list`, then `EXPLAIN`, then optional confirmed `sql --profile`
5. User provides only a vague symptom → `auth status`, `profile list --active`, `profile list --limit 20`, then ask for SQL/query_id if nothing relevant appears
6. No CLI available → use fallback SQL or provide exact command plan; do not diagnose without evidence

#### When user provides a query_id

1. `{{CLI}} profile get <query_id> --format json`
2. If profile fetch fails, still treat the failed fetch as evidence. Check whether the failure looks like eviction, wrong HTTP port, or connectivity; see Failure Handling below
3. For each table in `scanned_tables`, run `{{CLI}} tablet <db.table> --detail --format json`
4. If `tablet` shows stale stats (zero rows on a known-populated table), note this as a caveat — metadata can lag on new or tiny tables
5. Gather evidence, form hypotheses, recommend next checks

#### When user provides SQL but no query_id

1. Check recent runs first: `{{CLI}} profile list --format json` — scan for matching SQL text
2. If a recent run exists, use that profile instead of re-executing
3. If no recent run exists, run `{{CLI}} sql "EXPLAIN <query>" --format json`
4. If SQL looks expensive, unfamiliar, during peak hours, or could scan/join large tables, show the EXPLAIN evidence and ask before profiled execution
5. Only after the safety gate passes: `{{CLI}} sql "<query>" --profile --format json`
6. Extract `query_id` from response → continue with profile workflow above

#### When user gives only a vague symptom

1. `{{CLI}} auth status --format json` — verify MySQL and HTTP connectivity before query diagnosis
2. `{{CLI}} profile list --active --format json` — look for currently slow/running queries
3. `{{CLI}} profile list --limit 20 --format json` — look for recent slow profiles
4. If the user gives a workload keyword but not exact SQL, optionally use `{{CLI}} profile history "<keyword>" --days 7 --format json`
5. If nothing relevant appears, ask for query_id, SQL text, dashboard/report name, time window, and environment. Do not invent a query or DDL

#### When investigating a running query

1. `{{CLI}} profile list --active --format json` — find active queries
2. Wait for completion or ask user if they want to cancel/let it finish
3. Then fetch the profile with `profile get`

#### Regression comparison

- `{{CLI}} profile diff <slow_qid> <fast_qid> --format json` — operator-by-operator delta
- Focus on operators where time or rows changed significantly

#### Trend analysis

- `{{CLI}} profile history "<sql_pattern>" --days 7 --format json` — p50/p99 over time
- Look for gradual growth (data volume) vs sudden jump (schema change, partition change, cluster change)

#### When profile is unavailable or was not enabled

1. Try `{{CLI}} profile list --limit 20 --format json` for recent profiles
2. Try `{{CLI}} profile history "<sql_pattern>" --days 7 --format json` if a query pattern is known
3. Use `{{CLI}} sql "EXPLAIN <query>" --format json` and `{{CLI}} tablet <db.table> --detail --format json` as fallback evidence
4. Ask to rerun with `--profile` only after the safety gate passes

---

### Profile Output Fields

Key fields in `profile get` response:

| Section | Field | Meaning |
|---------|-------|---------|
| `summary` | `total_time_ms` | End-to-end latency |
| `query_stats` | `total_scan_rows` | Total rows scanned across all fragments |
| `query_stats` | `spilled_operators` | Count of operators that spilled to disk |
| `query_stats` | `blocked_operators` | Count of operators blocked on upstream |
| `operators[]` | `selectivity` | Input/output row ratio per operator |
| `operators[]` | `spilled` | Whether this operator spilled |
| `operators[]` | `shuffle_bytes` | Data shuffled across network |
| `operators[]` | `join_type` | shuffle / broadcast / colocated |
| `operators[]` | `peak_mem_bytes` | Peak memory for this operator |
| `operators[]` | `blocked_on_upstream` | Wait exceeded 2x exec time |
| `operators[]` | `cache_hit_pct` | Cache effectiveness |
| `operators[]` | `runtime_filters` | Runtime filter applied |
| `scanned_tables[]` | `tablet_skew` | Tablet size distribution ratio |
| `time_breakdown` | `plan` | Planning phase duration |

### Tablet Output Fields

Key fields in `tablet` response:

| Field | Meaning |
|-------|---------|
| `bucket_key` | Current HASH distribution column(s) |
| `bucket_count` | Number of buckets |
| `health.tablet_skew` | Ratio of max/avg tablet size |
| `sort_key` | Current sort key column order |
| `model` | DUPLICATE / UNIQUE / AGGREGATE |
| `total_rows` | Approximate row count (may lag on new tables) |

---

### Diagnostic Hypotheses

Each mapping below is a **hypothesis**, not a guaranteed root cause. Present as: evidence observed → likely explanation → what to check next → possible fix → when this conclusion may be wrong.

#### High scan selectivity

- **Evidence**: scan operator `selectivity` >> 100, or `total_scan_rows` vastly exceeds output rows
- **Likely**: sort key does not match the query's primary filter columns — Doris scans more data than necessary
- **Check next**: `{{CLI}} tablet <table>` → compare `sort_key` columns with the query's WHERE clause. Also check if an inverted index or BloomFilter could help
- **Possible fix**: move the high-selectivity filter column to sort key position 1 → `schema-keys-selectivity-first`. Or add a secondary index
- **Not always this**: high selectivity can also result from stale column stats causing bad partition pruning, or from querying across many partitions where the filter is only selective within each partition

#### Tablet skew

- **Evidence**: `health.tablet_skew` > 3.0, or `tablet --detail` shows one backend holding most data
- **Likely**: bucket key has low cardinality or a skewed value distribution
- **Check next**: `SHOW COLUMN STATS <table>` to verify cardinality of the bucket key. Check if a dominant value (e.g., NULL, default) concentrates data
- **Possible fix**: switch to a higher-cardinality bucket key, use composite key, or switch to RANDOM (DUP tables only) → `schema-bucket-composite-for-skew`, `schema-bucket-high-cardinality-key`
- **Not always this**: skew can also be caused by uneven partition sizes, recent data loading into a subset of partitions, or a tablet migration in progress

#### Large shuffle on JOIN

- **Evidence**: `shuffle_bytes` is large on a JOIN operator, or `join_type` = shuffle for a table that could use broadcast or colocation
- **Likely**: tables are not colocated and the smaller side exceeds the broadcast threshold
- **Check next**: check both tables' bucket keys and counts with `{{CLI}} tablet`. Check dimension table size (< 1GB usually broadcasts automatically)
- **Possible fix**: for small dimensions (< 1GB), ensure broadcast join + runtime filter are working. For large repeated joins, align bucket keys and counts for colocation → `usecase-star-schema-join`
- **Not always this**: shuffle is sometimes correct for large-large joins. The cost may also be dominated by the scan, not the shuffle itself

#### Spill to disk

- **Evidence**: `spilled` = true on aggregation, sort, or join operators; `spilled_operators` > 0
- **Likely**: operator's intermediate state exceeds available memory — often caused by high-cardinality GROUP BY or large hash join build side
- **Check next**: identify which operator spills and check its `peak_mem_bytes` and input row count. Check `exec_mem_limit` session variable
- **Possible fix**: pre-aggregate with sync MV to reduce runtime cardinality (`schema-mv-sync-rollup`), increase `exec_mem_limit`, reduce `parallel_pipeline_task_num`, or use approximate aggregation (BITMAP for count distinct)
- **Not always this**: occasional spill on very large queries is expected behavior, not a bug. Only investigate if spill correlates with unacceptable latency

#### Cache miss on repeated queries

- **Evidence**: `cache_hit_pct` near 0 on queries that run repeatedly
- **Likely**: data is not cached — could be cold partition access, cache eviction, or query/partition cache disabled
- **Check next**: is the query hitting time partitions that were just loaded? Is file cache enabled (storage-compute mode)? Check `cache_last_version_interval_second`
- **Possible fix**: `schema-cache-file-cache`, `schema-cache-query-partition`
- **Not always this**: the first run after data ingestion always misses. If ingestion is continuous, cache may never warm fully for the latest partition

#### Planning overhead

- **Evidence**: `time_breakdown.plan` is a large fraction of `total_time_ms`
- **Likely**: too many partitions for the planner to evaluate, complex query with many joins, or Nereids optimizer overhead
- **Check next**: count partitions with `SHOW PARTITIONS FROM <table>`. Check `time_breakdown.nereids_rewrite` and `nereids_analysis` sub-phases
- **Possible fix**: reduce partition count (coarser granularity), add partition pruning predicates to WHERE clause, or use prepared statements for repeated queries
- **Not always this**: complex multi-table queries naturally take longer to plan. Only a problem if plan time dominates execution time

#### Blocked on upstream

- **Evidence**: downstream operator has `blocked_on_upstream` flag or wait time >> exec time
- **Likely**: the upstream operator (usually scan or shuffle) is the real bottleneck — the downstream operator is just waiting for data
- **Check next**: identify the upstream operator and diagnose that one instead
- **Possible fix**: fix the upstream issue (bad scan, slow shuffle, etc.) — the downstream wait will resolve automatically
- **Not always this**: network issues or cluster resource contention can also cause temporary blocking

---

### Failure Handling

#### Profile fetch fails

- Profile may be evicted (Doris keeps profiles for a limited time, often 5-15 minutes)
- HTTP port may be misconfigured: Cloud mode uses 8080, self-hosted Doris uses 8030. `{{CLI}} auth status` shows `http_status` and `http_probe`
- FE may be unreachable: check the `served_by` and `fetch_attempts` fields in the error response
- **Recovery**: if profile is evicted, try `profile history` for trend data and `profile list` for nearby recent runs. Ask user to re-run with `--profile` only after the safety gate passes. If HTTP port is wrong, guide user to fix with `{{CLI}} auth add` (re-add environment with correct `--http-port`)

#### Tablet metadata lag

- Newly created or recently loaded tables may show `total_rows = 0` or stale sizes in `tablet` output
- This is normal — tablet metadata compaction and stats refresh have lag
- **Recovery**: note the caveat in your analysis. Use the profile's `total_scan_rows` as the actual row count signal instead of tablet metadata

#### Column stats unavailable

- `SHOW COLUMN STATS` may return empty if ANALYZE hasn't been run
- **Recovery**: note that cardinality estimates are unavailable. Recommend the user run `ANALYZE TABLE <table>` and revisit

#### Connection fails during investigation

- If `{{CLI}} auth status` shows `mysql_status: unreachable` or `http_status: unreachable`, diagnose the connection before continuing with query investigation
- For Cloud environments: cluster may be Suspended — check with `{{CLI}} cloud cluster get`
- For BYOC: may need SOCKS5 proxy

---

### Fallback SQL (When {{CLI}} is unavailable)

Use these via `mysql` client or any MySQL-compatible tool:

```sql
-- Table structure
SHOW CREATE TABLE db.table_name;

-- Query plan (pre-execution, does not run the query)
EXPLAIN <query>;

-- Tablet distribution and skew
SHOW DATA SKEW FROM db.table_name;

-- Column statistics (cardinality)
SHOW COLUMN STATS db.table_name;

-- Recent queries (requires FE HTTP access)
-- GET http://<fe_host>:<http_port>/rest/v2/manager/query/query_info?is_all_node=true

-- Fetch a specific profile by query_id (requires FE HTTP access)
-- GET http://<fe_host>:<http_port>/rest/v2/manager/query/profile/text/<query_id>?is_all_node=true
```

Limitations: no structured JSON, no `profile get` equivalent without HTTP API access, no `profile diff` or `profile history`. Analysis will be less precise — state this upfront.
