---
name: doris-best-practices
description: >
  Apache Doris table design and cluster sizing best practices.
  MUST USE when writing, reviewing, or optimizing Doris CREATE TABLE statements,
  partition/bucket strategies, data models, or cluster configurations.
  ALSO MUST USE whenever the doris-architecture-advisor skill produces DDL — apply
  the Pre-Flight Checklist to every CREATE TABLE before output.
  Also triggers on any workload design involving: IoT, analytics, dashboard, CDC,
  time-series, log analysis, real-time warehouse, point query, data platform, or
  any scenario where table design decisions are being made.
  Also triggers on replacing or migrating from legacy analytics/search/serving
  stacks such as Impala, Kudu, Elasticsearch/ES, Greenplum, Presto, HBase,
  Hive, Hadoop, Redis, or Lambda-style multi-engine data platforms, even when
  Apache Doris is not named explicitly.
  Also use when user provides an Apache Doris connection string or asks to get started.
  Also triggers on slow query investigation, query profiling, runtime performance
  diagnosis, tablet skew analysis, and table health checks — any scenario where
  runtime evidence (profile output, tablet distribution) informs optimization.
  Cluster lifecycle, billing, and networking are managed-service operations, out of
  scope here — use your platform's cluster-management console for those.
license: Apache-2.0
metadata:
  author: tomz-alt
  version: "0.1.0"
---

# Apache Doris Best Practices

> Problem-first table design intelligence for Apache Doris.
> 37 rules, 7 use case templates, 4 sizing guides.
> All details in `references/` directory.

---

## 1 ▸ Problem-First Routing

### I need to build…

| Problem | Template(s) | Key Rules |
|---------|-------------|-----------|
| Real-time log/event analytics | `usecase-log-event` | DUPLICATE, RANGE partition, dynamic TTL, ZSTD |
| CDC / MySQL sync to Doris | `usecase-cdc-sync` | UNIQUE MoW, sequence_col, HASH bucket |
| Dashboard with pre-aggregated metrics | `usecase-dashboard-metrics` | AGGREGATE, BITMAP_UNION, sync MV |
| User-facing API with low-latency point queries | `usecase-point-query` | UNIQUE MoW, store_row_column, BloomFilter |
| Star schema with JOIN-heavy analytics | `usecase-star-schema-join` | Colocation, same bucket key/count |
| Small dimension / lookup table | `usecase-dimension-lookup` | DUPLICATE, RANDOM bucket, 3 buckets |
| Observability (logs + traces + metrics) | `usecase-observability` | 3 tables: DUP logs, DUP traces, AGG metrics |
| Vehicle/fleet tracking | `usecase-log-event` + `usecase-point-query` | Time-series + point-query hybrid |
| E-commerce order analytics | `usecase-star-schema-join` + `usecase-dashboard-metrics` | Star schema + AGG rollups |
| Full-text search / content search | `schema-index-text-search` | Inverted index, MATCH, BM25 |
| User behavior / funnel analysis | `schema-types-bitmap-count-distinct` | BITMAP_UNION, bitmap_intersect |
| Semi-structured JSON data | `schema-types-variant-json` | VARIANT type, schema_template |

### My query is slow after evidence shows…

For live slow-query or runtime diagnosis, do **not** use this table as the first response. First read `references/cli-investigation.md` and collect or attempt evidence (`profile get`, `profile list`, `profile history`, `tablet`, `EXPLAIN`, or `auth status`). Use this table only after evidence points to the symptom.

| Symptom | Check These Rules | Quick Fix |
|---------|------------------|-----------|
| Full table scan on WHERE clause | `schema-keys-selectivity-first` | Move filtered column to sort key position 1 |
| JOINs are slow / shuffle | `usecase-star-schema-join` | Small dims (<1GB): broadcast + runtime filter. Large: colocation |
| COUNT DISTINCT is slow | `schema-types-bitmap-count-distinct` | Switch to BITMAP_UNION aggregation |
| LIKE '%keyword%' is slow | `schema-index-ngram-for-like` | Add NGram BloomFilter index |
| Point query latency too high | `usecase-point-query` | Enable store_row_column + Prepared Statement |
| Storage growing too fast | `schema-partition-auto-on-demand` + `schema-props-compression` | AUTO PARTITION + ZSTD compression + scheduled DROP PARTITION |
| Sync MV not being used | `schema-mv-sync-rollup` | Use raw columns (not date_trunc) in MV GROUP BY; unique aliases |
| Async MV rewrite fails | `schema-mv-async-join` + `schema-mv-async-limits` | Check State/RefreshState; query MV directly if predicate fails |
| Data skew / hot tablets | `schema-bucket-composite-for-skew` | Composite bucket key or RANDOM |
| Import fails / data version error | `schema-mv-async-limits` | Check concurrent MV refresh limit (max 3) |
| VARCHAR in key kills perf | `schema-keys-fixed-length-types` | Move VARCHAR after fixed-length types |
| Writes slow on UNIQUE table | `schema-model-prefer-mow` | Ensure MoW is enabled (not MoR) |

---

## 2 ▸ Pre-Flight Checklist (Before Any CREATE TABLE)

Run through this checklist in order. Each step references the relevant rule:

- [ ] **Data model** — UNIQUE (updates?) vs DUPLICATE (append?) vs AGGREGATE (pre-agg only?) → `schema-model-choose-for-workload`
- [ ] **Partition strategy** — Time-series? AUTO PARTITION preferred. Small table? Skip. Do NOT combine AUTO with dynamic_partition. → `schema-partition-*`
- [ ] **Bucket key + count** — HASH on JOIN key. Calculate explicit count: `daily_GB / target_tablet_GB`. Use explicit fallback counts when volume is unknown: 3 for small dimensions, 8 for medium tables, 16-32 for large daily fact tables. → `schema-bucket-*`
- [ ] **Sort key order** — High-selectivity first, fixed-length before VARCHAR → `schema-keys-*`
- [ ] **Data types** — Native types, not STRING. DECIMAL not FLOAT. → `schema-types-*`
- [ ] **Indexes** — BloomFilter for equality, Inverted for text, NGram for LIKE → `schema-index-*`
- [ ] **Properties** — MoW enabled? Compression? Cloud mode replication_num=1? → `schema-props-*`
- [ ] **DDL hard constraints** (Apache Doris rejects DDL if any violated):
  - UNIQUE KEY + PARTITION BY RANGE → partition column MUST be in the UNIQUE KEY: `UNIQUE KEY(id, dt) PARTITION BY RANGE(dt)`
  - Key columns must be the FIRST N columns in schema, same order — put key cols first, non-key after. Example: `UNIQUE KEY(account_id, symbol)` means schema must start with `account_id, symbol, ...` — never place non-key columns between key columns
  - `store_row_column = "true"` only works on UNIQUE MoW — NOT on AGGREGATE or DUPLICATE
  - AUTO PARTITION requires `date_trunc()` AND empty parens: `AUTO PARTITION BY RANGE(date_trunc(col, 'day')) ()` — bare column name fails, missing `()` fails
  - Dynamic partition requires explicit `PARTITION BY RANGE(col) ()` clause in DDL — properties alone are not enough
  - Do not set `dynamic_partition.buckets`; put the numeric count only in `DISTRIBUTED BY HASH(col) BUCKETS N`
  - `compaction_policy = "time_series"` only for DUPLICATE tables — fails on UNIQUE
  - Async MV refresh: use `REFRESH AUTO ON SCHEDULE EVERY 10 MINUTE` or `REFRESH COMPLETE ON SCHEDULE EVERY 10 MINUTE` — NOT `REFRESH SCHEDULE EVERY`, NOT `REFRESH ASYNC EVERY(INTERVAL ...)`. Minimum interval: 1 MINUTE
  - MV using `NOW()`/`CURDATE()`: add `PROPERTIES ("enable_nondeterministic_function" = "true")`
  - BOOLEAN defaults must be quoted: `DEFAULT "true"` not `DEFAULT TRUE`
  - BloomFilter index: use `PROPERTIES ("bloom_filter_columns" = "col1,col2")` — NOT inline `INDEX ... USING BLOOM FILTER`
  - AGGREGATE column syntax: aggregation function BEFORE default: `col BIGINT SUM DEFAULT "0"` — NOT `col BIGINT DEFAULT "0" SUM`
  - AGGREGATE `DEFAULT "null"` only works for VARCHAR — fails on INT, DATE, DECIMAL, BIGINT. Omit DEFAULT entirely for REPLACE_IF_NOT_NULL on non-string types: `vip_level INT REPLACE_IF_NOT_NULL` (not `DEFAULT "null"`)
  - `enable_unique_key_partial_update` is a session variable, NOT a table property
  - Full details: `schema-ddl-gotchas`

---

## 2b ▸ DDL Templates (copy the closest match, customize columns)

For each CREATE TABLE, select the closest template below. Customize column names, types, bucket count, and partition settings. Do NOT write DDL from scratch.

### T1: Append-only events/logs (DUPLICATE)
```sql
CREATE TABLE events (
    entity_id    VARCHAR(64)  NOT NULL,
    event_time   DATETIME     NOT NULL,
    event_type   VARCHAR(50)  NOT NULL,
    payload      VARIANT
) DUPLICATE KEY(entity_id, event_time, event_type)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(entity_id) BUCKETS 10
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-90",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",
    "compaction_policy" = "time_series",
    "replication_num" = "1"
);
```

### T2: Updatable with partition (UNIQUE MoW + CDC)
```sql
CREATE TABLE orders (
    order_id     BIGINT       NOT NULL,
    order_time   DATETIME     NOT NULL,
    update_time  DATETIME     NOT NULL,
    status       VARCHAR(20),
    amount       DECIMAL(18,2)
) UNIQUE KEY(order_id, order_time)
PARTITION BY RANGE(order_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 5
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
```

### T3: Small dimension / lookup (UNIQUE, no partition)
```sql
CREATE TABLE dim_product (
    product_id   INT          NOT NULL,
    name         VARCHAR(200),
    category     VARCHAR(50)
) UNIQUE KEY(product_id)
DISTRIBUTED BY HASH(product_id) BUCKETS 3
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "replication_num" = "1"
);
```

### T4: Pre-aggregated KPIs (AGGREGATE)
```sql
CREATE TABLE daily_kpi (
    stat_date    DATE         NOT NULL,
    dimension    VARCHAR(50)  NOT NULL,
    metric_sum   BIGINT       SUM DEFAULT "0",
    metric_max   DOUBLE       MAX DEFAULT "0",
    unique_users BITMAP       BITMAP_UNION
) AGGREGATE KEY(stat_date, dimension)
PARTITION BY RANGE(stat_date) ()
DISTRIBUTED BY HASH(dimension) BUCKETS 3
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "1",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
```

### T5: Point query / API serving (UNIQUE MoW + row store)
```sql
CREATE TABLE user_profiles (
    user_id      BIGINT       NOT NULL,
    update_time  DATETIME     NOT NULL,
    name         VARCHAR(100),
    data         VARIANT
) UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "store_row_column" = "true",
    "light_schema_change" = "true",
    "replication_num" = "1"
);
```

---

## 3 ▸ Connection & CLI

Apache Doris speaks the MySQL protocol, so the **always-available** path is any MySQL-compatible client (`mysql`) plus SQL and the FE HTTP REST API. Some distributions also ship an **optional management CLI** (referred to here as `doriscli`) that adds ergonomic profiling and diagnostics commands — use it when your distribution provides one, otherwise use the native path.

### Detect the optional CLI

Before running any queries, detect whether the CLI binary is available:

1. Check `DORIS_CLI_PATH` env var — if set, use that binary path
2. `command -v doriscli` — use from PATH
3. If none available: fall back to `mysql` client (see `references/start-*.md`)

### When doriscli is available, prefer it for all operations:

| Task | doriscli Command |
|------|-----------------|
| Run SQL | `doriscli sql "SELECT ..."` |
| DDL inspection | `doriscli sql "SHOW CREATE TABLE db.t"` |
| Table/tablet health | `doriscli tablet db.t` (overview) or `doriscli tablet db.t --detail` |
| Profile a slow query | `doriscli sql "SELECT ..." --profile` → captures query_id |
| Get query profile | `doriscli profile get <qid>` or `--full` for complete diagnosis |
| Compare fast vs slow | `doriscli profile diff <slow_qid> <fast_qid>` |
| Performance trend | `doriscli profile history <sql_pattern> --days 7` |
| Test connection | `doriscli auth status` |
| Switch environment | `doriscli use <name>` |

### Runtime Query Investigation

For slow queries or runtime performance issues, read `references/cli-investigation.md`.

- **Evidence first is mandatory**: collect or attempt profile, tablet, DDL, stats, EXPLAIN, history, active-query, or connection evidence before forming hypotheses. If evidence cannot be collected locally, state that and provide the exact commands to run
- **Prefer existing profiles**: use `profile get <query_id>`, `profile list`, or `profile history` before re-executing SQL
- **Proactive discovery**: for vague slow-query reports, start with `auth status`, `profile list --active`, and recent `profile list` before asking the user for more context
- **Safety gate**: before running user SQL with `--profile`, check whether it is safe (no DDL, no mutation, no unbounded scan). For unknown, peak-hour, or expensive SQL, run `doriscli sql "EXPLAIN <query>" --format json` first and ask confirmation or request an existing query_id
- **Hypotheses, not verdicts**: diagnostic mappings are heuristics. Present evidence, likely cause, what to check next, and when the conclusion may be wrong
- If doriscli is unavailable, fall back to SQL commands listed in the reference
- Always use `--format json` for structured agent-readable output

### Quick-start guides

- `references/start-self-hosted.md` — Self-hosted / BYOC / on-prem
- Cloud mode (storage-compute) connection differs only in the HTTP port (8080 vs 8030) — same guide applies

---

## 4 ▸ Cluster Sizing

Sizing guides are in:
- `references/sizing-fe.md` — FE node sizing
- `references/sizing-be-integrated.md` — BE sizing (integrated storage)
- `references/sizing-be-cloud.md` — BE sizing (cloud / storage-compute)
- `references/sizing-storage-formula.md` — Storage calculation formula

---

## 5 ▸ Rule Index by Category

### Data Model — CRITICAL (4 rules)
- `schema-model-choose-for-workload` — DUP vs UNIQUE vs AGG decision tree
- `schema-model-prefer-mow` — Always MoW for UNIQUE tables
- `schema-model-avoid-agg-for-updates` — AGG cannot UPDATE/DELETE
- `schema-model-sequence-col-for-cdc` — Sequence column for out-of-order CDC

### Partition Strategy — CRITICAL (4 rules)
- `schema-partition-range-for-timeseries` — RANGE for time-series
- `schema-partition-dynamic-ttl` — Dynamic partition for automated TTL
- `schema-partition-auto-on-demand` — AUTO for sporadic data
- `schema-partition-skip-for-small` — Skip partitioning under 1 GB

### Bucket Strategy — CRITICAL (5 rules)
- `schema-bucket-hash-vs-random` — HASH for pruning, RANDOM for DUP only
- `schema-bucket-high-cardinality-key` — Choose high-cardinality column
- `schema-bucket-composite-for-skew` — Composite key to fix data skew
- `schema-bucket-target-size` — Target 1-10 GB per tablet
- `schema-bucket-cloud-mandatory-hash` — Cloud MoW requires HASH

### Sort Key — CRITICAL (5 rules)
- `schema-keys-selectivity-first` — High selectivity first
- `schema-keys-fixed-length-types` — Fixed-length before VARCHAR
- `schema-keys-prefix-index-limits` — 36 bytes max, VARCHAR terminates it
- `schema-keys-cluster-key-for-mow` — Cluster key for UNIQUE tables
- `schema-keys-avoid-float` — No FLOAT/DOUBLE in sort key

### Data Types — HIGH (5 rules)
- `schema-types-native-vs-string` — Native types, not STRING
- `schema-types-zonemap-limitations` — JSON/ARRAY disable ZoneMap
- `schema-types-variant-json` — VARIANT for semi-structured JSON
- `schema-types-bitmap-count-distinct` — BITMAP_UNION for exact count-distinct
- `schema-types-doris-specifics` — DATETIME precision, VARCHAR vs STRING

### Indexes — HIGH (7 rules)
- `schema-index-bloomfilter` — BloomFilter for equality
- `schema-index-inverted` — Inverted for text/range
- `schema-index-ngram-for-like` — NGram for LIKE %pattern%
- `schema-index-bitmap` — Bitmap for medium cardinality
- `schema-index-vector` — HNSW/IVF for ANN search
- `schema-index-text-search` — Full-text MATCH + BM25

### Query Acceleration — HIGH (3 rules)
- `schema-mv-sync-rollup` — Sync MV for single-table aggregation
- `schema-mv-async-join` — Async MV for multi-table JOIN
- `schema-mv-async-limits` — Operational limits (50M rows, 3 concurrent)

### Table Properties — HIGH/MEDIUM (2 rules)
- `schema-props-cloud-forced` — Cloud mode forced properties
- `schema-props-compression` — LZ4 vs ZSTD compression

### Caching — MEDIUM (2 rules)
- `schema-cache-file-cache` — File cache for cloud mode
- `schema-cache-query-partition` — Query and partition cache
