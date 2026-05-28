# Apache Doris — Complete Best Practice Reference

> All 37 rules, 7 use case templates, and sizing guides.

---

## Use Case Templates

## Use Case: CDC / Operational Data Sync
For replicating operational databases (MySQL, PostgreSQL) where rows are frequently updated or deleted.
### Template
```sql
CREATE TABLE users_sync (
    user_id BIGINT NOT NULL,
    tenant_id INT NOT NULL,
    update_time DATETIME NOT NULL,
    name VARCHAR(100),
    email VARCHAR(200),
    status TINYINT
) ENGINE=OLAP
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- CDC table: ~10 GB compressed
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "light_schema_change" = "true"
);
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | UNIQUE (MoW) | Enables UPDATE/DELETE. MoW gives fast reads without merge-sort. |
| **Sequence col** | `update_time` | Guarantees out-of-order CDC events don't overwrite newer data. |
| **Bucket** | HASH on `user_id` (= primary key) | Point lookups on PK are pruned to one tablet. |
| **Partition** | None | CDC tables are often small-to-medium; partition only if > 100GB. |
### Customization Points
- **Large CDC tables (> 100GB):** Add `PARTITION BY RANGE(update_time) ()` with dynamic partition
- **Composite primary key:** Use `UNIQUE KEY(tenant_id, user_id)` for multi-tenant data
- **Partial column updates:** Set `"enable_unique_key_partial_update" = "true"`

---

## Use Case: Dashboard / Pre-Aggregated Metrics
For pre-computing dashboard numbers: daily sales, ad click totals, user activity summaries.
### Template
```sql
CREATE TABLE daily_sales_metrics (
    dt DATE NOT NULL, store_id INT NOT NULL,
    total_revenue DECIMAL(15,2) SUM DEFAULT "0",
    max_transaction DECIMAL(15,2) MAX DEFAULT "0",
    order_count BIGINT SUM DEFAULT "0",
    unique_buyers BITMAP BITMAP_UNION
) ENGINE=OLAP AGGREGATE KEY(dt, store_id)
PARTITION BY RANGE(dt) ()
DISTRIBUTED BY HASH(store_id) BUCKETS 5  -- pre-aggregated metrics: ~10 GB compressed
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="MONTH",
    "dynamic_partition.start"="-12","dynamic_partition.end"="1","dynamic_partition.prefix"="p");
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | AGGREGATE | Values auto-aggregate (SUM, MAX, BITMAP_UNION) on ingestion. |
| **BITMAP** | `BITMAP_UNION` for unique_buyers | Exact count-distinct without storing raw user IDs. |
### Anti-Pattern
```sql
-- BAD: Using DUPLICATE for dashboard data you'll always aggregate
CREATE TABLE daily_sales_metrics (dt DATE, store_id INT, revenue DECIMAL(15,2))
DUPLICATE KEY(dt, store_id);
-- Every query must re-aggregate billions of rows at query time.
```

---

## Use Case: Small Dimension / Lookup Table
For small reference tables (< 1 GB): products, stores, countries, config values.
### Template
```sql
CREATE TABLE stores (
    store_id INT NOT NULL, region VARCHAR(20) NOT NULL,
    city VARCHAR(50), manager_name VARCHAR(100)
) ENGINE=OLAP DUPLICATE KEY(store_id)
DISTRIBUTED BY RANDOM BUCKETS 3
PROPERTIES ("replication_num" = "3");  -- Use "1" for cloud mode
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | DUPLICATE | Dimension data is reference data — rarely updated. |
| **Partition** | None | Table is tiny (< 1 GB). Partitioning adds overhead, not benefit. |
| **Bucket** | RANDOM, 3 buckets | Perfectly even distribution for small data. |
### Customization Points
- **Updated dimensions:** Switch to `UNIQUE KEY(store_id)` with MoW if dimension data changes
- **Colocation JOINs:** Switch to `HASH(store_id)` and match the fact table's bucket count

---

## Use Case: Time-Series Logs & Events
For immutable, append-only data: application logs, click events, IoT sensor readings, audit trails.
### Template
```sql
CREATE TABLE app_events (
    event_time DATETIME NOT NULL,
    app_id INT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    user_id BIGINT,
    payload STRING
) ENGINE=OLAP
DUPLICATE KEY(event_time, app_id, event_type)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(app_id) BUCKETS 10  -- high-volume logs: ~50 GB/day compressed
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd"
);
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | DUPLICATE | Logs are immutable — no updates/deletes needed. Fastest scan speed. |
| **Partition** | Dynamic RANGE by DAY | Auto-creates daily partitions, auto-drops old ones (TTL via `start`). |
| **Bucket** | HASH on `app_id` | High cardinality, commonly filtered in WHERE. |
| **Sort Key** | `(event_time, app_id, event_type)` | Time-first enables range scans; app_id enables prefix pruning. |
| **Compression** | ZSTD | Log data has high redundancy — ZSTD compresses 2-3x better than LZ4. |
### Customization Points
- **Retention:** Change `dynamic_partition.start` (e.g., `"-30"` for 30 days)
- **Partition granularity:** `"HOUR"` for very high volume or `"MONTH"` for low volume
- **Bucket key:** If you mostly filter by `user_id`, use `HASH(user_id)` instead
- **Add text search:** Add `INDEX idx_payload(payload) USING INVERTED` for log message search

---

## Use Case: Observability Platform
For building a full observability stack: logs + metrics + traces.
### Table 1: Logs (DUPLICATE)
```sql
CREATE TABLE otel_logs (
    log_time DATETIME NOT NULL, service_name VARCHAR(100) NOT NULL,
    severity VARCHAR(10) NOT NULL, trace_id VARCHAR(32), span_id VARCHAR(16),
    body TEXT, resource_attributes STRING,
    INDEX idx_body(body) USING INVERTED PROPERTIES("parser" = "unicode")
) ENGINE=OLAP DUPLICATE KEY(log_time, service_name, severity)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 10  -- high-volume logs: ~100 GB/day x 0.05 ZSTD / 2 GB
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="DAY",
    "dynamic_partition.start"="-7","dynamic_partition.end"="3",
    "dynamic_partition.prefix"="p","compression"="zstd",
    "bloom_filter_columns"="trace_id");
```
### Table 2: Traces (DUPLICATE)
```sql
CREATE TABLE otel_traces (
    start_time DATETIME NOT NULL, service_name VARCHAR(100) NOT NULL,
    trace_id VARCHAR(32) NOT NULL, span_id VARCHAR(16) NOT NULL,
    parent_span_id VARCHAR(16), operation_name VARCHAR(200),
    duration_ms BIGINT, status_code TINYINT
) ENGINE=OLAP DUPLICATE KEY(start_time, service_name, trace_id)
PARTITION BY RANGE(start_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 3  -- traces: lower volume than logs, small per partition
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="DAY",
    "dynamic_partition.start"="-7","dynamic_partition.end"="3",
    "dynamic_partition.prefix"="p","compression"="zstd",
    "bloom_filter_columns"="trace_id");
```
### Table 3: Metrics (AGGREGATE)
```sql
CREATE TABLE otel_metrics (
    metric_time DATETIME NOT NULL, service_name VARCHAR(100) NOT NULL,
    metric_name VARCHAR(200) NOT NULL,
    value DOUBLE SUM DEFAULT "0", count BIGINT SUM DEFAULT "0"
) ENGINE=OLAP AGGREGATE KEY(metric_time, service_name, metric_name)
PARTITION BY RANGE(metric_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 3  -- pre-aggregated metrics: small per partition
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="DAY",
    "dynamic_partition.start"="-30","dynamic_partition.end"="3","dynamic_partition.prefix"="p");
```
### Design Principles
- **Shared bucket key:** All tables use `HASH(service_name)` for potential colocation JOINs
- **Short retention for logs/traces:** 7-day TTL; **Longer for metrics:** 30-day TTL
- **Text search on logs:** Inverted index on `body` with unicode parser
- **Trace correlation:** BloomFilter on `trace_id` for fast trace lookup

---

## Use Case: User-Facing Point Query Analytics
For serving real-time analytics through APIs with low-latency, high-concurrency requirements.
### Template
```sql
CREATE TABLE user_profiles (
    user_id BIGINT NOT NULL, tenant_id INT NOT NULL,
    name VARCHAR(100), email VARCHAR(200), last_login DATETIME,
    total_orders INT, lifetime_value DECIMAL(12,2)
) ENGINE=OLAP UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- user profiles: ~10 GB compressed
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "store_row_column" = "true",
    "light_schema_change" = "true",
    "bloom_filter_columns" = "tenant_id"
);
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | UNIQUE MoW | Fast reads (no merge-sort at query time) |
| **store_row_column** | `true` | Enables row-store mode for point queries — reads full row from one I/O |
| **BloomFilter** | On `tenant_id` | Skips tablets that don't contain the tenant |
### Optimized Point Query Pattern
```sql
SELECT * FROM user_profiles WHERE user_id = 12345;
-- With Prepared Statement for high concurrency:
PREPARE stmt FROM 'SELECT * FROM user_profiles WHERE user_id = ?';
SET @uid = 12345; EXECUTE stmt USING @uid;
```

---

## Use Case: Star Schema / JOIN-Heavy Analytics
Uses colocation to ensure JOINs execute locally without network shuffle.
### Fact Table
```sql
CREATE TABLE fact_orders (
    order_date DATE NOT NULL, order_id BIGINT NOT NULL,
    user_id INT NOT NULL, store_id INT NOT NULL, product_id INT NOT NULL,
    amount DECIMAL(12,2), quantity INT
) ENGINE=OLAP DUPLICATE KEY(order_date, order_id)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(store_id) BUCKETS 16
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="MONTH",
    "dynamic_partition.start"="-24","dynamic_partition.end"="1",
    "dynamic_partition.prefix"="p",
    "colocate_with"="group_orders");
```
### Dimension Table (colocated)
```sql
CREATE TABLE dim_stores (
    store_id INT NOT NULL, region VARCHAR(20), city VARCHAR(50), manager_name VARCHAR(100)
) ENGINE=OLAP DUPLICATE KEY(store_id)
DISTRIBUTED BY HASH(store_id) BUCKETS 16
PROPERTIES ("colocate_with" = "group_orders");
```
### Colocation Rules — ALL must match:
1. Same `colocate_with` group name
2. Same bucket key column(s) and same column types
3. Same bucket count
4. Same replication_num

---

## Data Model Rules

## AGGREGATE Model Cannot UPDATE or DELETE

**Impact: CRITICAL — AGG tables do not support UPDATE or DELETE statements.**

The AGGREGATE model auto-merges rows with the same key using aggregation functions (SUM, MAX, REPLACE, etc). This means:
- No `UPDATE` statement support
- No `DELETE` statement support
- No CDC pipeline compatibility (cannot reflect deletes)

**Exception: REPLACE_IF_NOT_NULL** — The one case where AGG can do partial updates. Columns with `REPLACE_IF_NOT_NULL` will only update when the incoming value is non-NULL. This allows partial column updates in AGG model, but still no DELETE.

**Incorrect:**

```sql
-- BAD: AGG for data that needs updates
CREATE TABLE orders (
    order_id BIGINT AGGREGATE KEY,
    status VARCHAR(20) REPLACE,
    amount DECIMAL(12,2) REPLACE
) AGGREGATE KEY(order_id);
-- Cannot DELETE cancelled orders!
```

**Correct:**

```sql
-- GOOD: UNIQUE MoW for updatable data
CREATE TABLE orders (
    order_id BIGINT NOT NULL,
    status VARCHAR(20),
    amount DECIMAL(12,2)
) UNIQUE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 5  -- ~10 GB compressed
PROPERTIES ("enable_unique_key_merge_on_write" = "true");
```

Reference: [Aggregate Model](https://doris.apache.org/docs/table-design/data-model/aggregate)

---

## Choose Data Model for Workload

**Impact: CRITICAL — Data model cannot be changed after table creation.**

| Model | Use When | Key Trait |
|-------|----------|-----------|
| DUPLICATE | Append-only data (logs, events, clicks) | Fastest scan, keeps all rows |
| UNIQUE (MoW) | Rows are updated/deleted (CDC, user data) | Dedup on primary key, supports DELETE |
| AGGREGATE | Pre-aggregated metrics only (counters, sums) | Auto-aggregates on ingest |

**Decision rule:** If you need UPDATE or DELETE → UNIQUE MoW. If append-only → DUPLICATE. Only use AGGREGATE when you will *never* query raw rows.

**Incorrect:**

```sql
-- BAD: Using AGGREGATE for a table that needs updates
CREATE TABLE users (
    user_id BIGINT AGGREGATE KEY,
    name VARCHAR(100) REPLACE,
    email VARCHAR(200) REPLACE
) AGGREGATE KEY(user_id);
-- Cannot DELETE rows. Cannot run UPDATE statements.
```

**Correct:**

```sql
-- GOOD: UNIQUE MoW for updatable data
CREATE TABLE users (
    user_id BIGINT NOT NULL,
    name VARCHAR(100),
    email VARCHAR(200)
) UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- ~10 GB compressed
PROPERTIES ("enable_unique_key_merge_on_write" = "true");
```

Reference: [Data Model Overview](https://doris.apache.org/docs/table-design/data-model/overview)

---

## Always Use Merge-on-Write (MoW) for UNIQUE Tables

**Impact: CRITICAL — MoR requires runtime merge-sort, making reads 2-10× slower.**

Since Doris 2.1, MoW is the default. For older versions, always set explicitly:

```sql
PROPERTIES ("enable_unique_key_merge_on_write" = "true")
```

**MoW vs MoR:**

| Feature | MoW | MoR |
|---------|-----|-----|
| Read speed | Fast (pre-merged) | Slow (merge at query) |
| Write speed | Slightly slower | Faster writes |
| DELETE support | Yes | Yes |
| Partial update | Yes | Limited |

**Always use MoW** unless you have a write-heavy workload with minimal reads.

Reference: [Unique Key Model](https://doris.apache.org/docs/table-design/data-model/unique)

---

## Sequence Column for Out-of-Order CDC

**Impact: HIGH — CDC events may arrive out of order; older records can overwrite newer ones.**

When using UNIQUE KEY with CDC (Flink CDC, Debezium, Canal), set a sequence column to guarantee ordering:

```sql
CREATE TABLE users (
    user_id BIGINT NOT NULL,
    update_time DATETIME NOT NULL,
    name VARCHAR(100),
    email VARCHAR(200)
) UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- CDC table: ~10 GB compressed
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time"
);
```

**How it works:** When two rows have the same primary key, Doris keeps the one with the *higher* sequence column value, regardless of arrival order.

**When to use:** Any CDC pipeline where events may arrive out of order (network delays, reprocessing, multiple sources).

Reference: [Sequence Column](https://doris.apache.org/docs/table-design/data-model/unique#sequence-column)

---

## Partition Rules

## AUTO PARTITION for Sporadic Data

**Impact: HIGH — Avoids creating empty partitions for dates with no data.**

Use AUTO PARTITION when data arrival is unpredictable (not every day/month has data):

```sql
CREATE TABLE sparse_events (
    event_time DATETIME NOT NULL,
    user_id BIGINT,
    event_type VARCHAR(50)
) DUPLICATE KEY(event_time, user_id)
AUTO PARTITION BY RANGE(date_trunc(event_time, 'month'))
()
DISTRIBUTED BY HASH(user_id) BUCKETS 5;  -- sporadic events: ~10 GB compressed
```

**When to use AUTO vs DYNAMIC:**
- **Dynamic:** Continuous data (logs, metrics) — pre-creates future partitions
- **Auto:** Sporadic data (user uploads, batch jobs) — creates only when data arrives

Reference: [Auto Partition](https://doris.apache.org/docs/table-design/data-partitioning/auto-partitioning)

---

## Dynamic Partition for Automated Data Lifecycle

**Impact: HIGH — Automates partition creation and TTL-based data cleanup.**

Key properties:
- `time_unit`: DAY, WEEK, MONTH
- `start`: Negative number = how many units to keep (TTL). E.g., `"-7"` keeps 7 days.
- `end`: Positive number = how many future partitions to pre-create
- `buckets`: AUTO or fixed number per partition

```sql
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);
```

**Warning: Do not use dynamic partition for tables with < 20 million rows.** For small tables, it creates wasteful empty partitions that go unnoticed and add unnecessary metadata overhead. Use a single partition or no partition instead.

Reference: [Dynamic Partition](https://doris.apache.org/docs/table-design/data-partitioning/dynamic-partitioning)

---

## RANGE Partition on Time Column for Time-Series

**Impact: CRITICAL — Partition key cannot be changed after table creation.**

For any table with a time column (logs, events, metrics), use RANGE partition:

```sql
PARTITION BY RANGE(event_time) ()
```

Combined with dynamic partitioning, this enables:
- **Partition pruning:** `WHERE event_time > '2025-01-01'` only scans relevant partitions
- **TTL:** Old partitions are auto-dropped
- **Parallel loading:** Each partition can be loaded independently

**Incorrect:**

```sql
-- BAD: No partition on a time-series table
CREATE TABLE events (
    event_time DATETIME, user_id BIGINT, data STRING
) DUPLICATE KEY(event_time)
DISTRIBUTED BY HASH(user_id) BUCKETS 8;
-- Every query scans ALL data, no TTL possible
```

**Correct:**

```sql
CREATE TABLE events (
    event_time DATETIME NOT NULL, user_id BIGINT, data STRING
) DUPLICATE KEY(event_time, user_id)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 10  -- time-series events: ~50 GB/day compressed
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);
```

Reference: [Range Partition](https://doris.apache.org/docs/table-design/data-partitioning/range-partitioning)

---

## Skip Partitioning for Small Tables (< 1 GB)

**Impact: HIGH — Unnecessary partitioning on small tables wastes metadata and hurts performance.**

If a table is under 1 GB total, do not partition it. Just use bucketing:

```sql
-- GOOD: Small dimension table, no partition needed
CREATE TABLE dim_countries (
    country_code VARCHAR(3) NOT NULL,
    country_name VARCHAR(100),
    region VARCHAR(50)
) DUPLICATE KEY(country_code)
DISTRIBUTED BY HASH(country_code) BUCKETS 3;
```

**Rule of thumb:**
- < 1 GB → No partition
- 1-100 GB → Consider partition if time-series
- > 100 GB → Always partition

Reference: [Data Partitioning](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)

---

## Bucket Rules

## Cloud Mode Requires HASH Bucketing for MoW

**Impact: HIGH — UNIQUE MoW tables in cloud mode must use HASH bucketing.**

In Cloud mode (storage-compute separation), RANDOM bucketing is not supported for UNIQUE KEY tables with MoW enabled.

```sql
-- GOOD: Cloud MoW with HASH
CREATE TABLE users (...)
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- cloud MoW: ~10 GB compressed
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "replication_num" = "1"  -- cloud mode
);
```


---

## Use Composite Bucket Key to Fix Data Skew

**Impact: HIGH (Single skewed bucket key concentrates data; composite key distributes it evenly)**

When a single column has uneven distribution (some values appear much more than others), use a composite bucket key.

**Incorrect (single skewed key):**

```sql
-- BAD: site_id 54321 has 80% of traffic → bucket_4 is 80% of data
CREATE TABLE site_access (
    site_id INT, city_code INT, pv BIGINT
) DUPLICATE KEY(site_id, city_code)
DISTRIBUTED BY HASH(site_id) BUCKETS 16;
```

**Correct (composite key):**

```sql
-- GOOD: combining site_id + city_code distributes the hot site across cities
CREATE TABLE site_access (
    site_id INT, city_code INT, pv BIGINT
) DUPLICATE KEY(site_id, city_code)
DISTRIBUTED BY HASH(site_id, city_code) BUCKETS 16;
-- Data for site_id=54321 is now spread across multiple buckets by city.
```

**When to use composite keys:**
- One column dominates traffic (e.g., one large customer)
- Single-column hash creates visible hot tablets
- Detect with: `SHOW TABLETS FROM table_name` and check size distribution

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)

---

## HASH Bucket for Pruning; RANDOM Only for DUP Full-Scans

**Impact: CRITICAL — Bucket key cannot be changed after table creation.**

- **HASH bucket:** Filters on the bucket column prune to a single tablet → fast point queries
- **RANDOM bucket:** Guarantees perfectly even distribution but no query pruning

| Feature | HASH | RANDOM |
|---------|------|--------|
| Query pruning | Yes (WHERE on bucket col) | No |
| Data distribution | Depends on column cardinality | Always even |
| Supported models | ALL | DUPLICATE only |

**30% Skew Rule:** If your chosen bucket column has >30% data skew (one value dominates), you must either use RANDOM bucketing or switch to a composite key. Detect with `SHOW TABLETS FROM table_name` and check size distribution.

**Incorrect:**

```sql
-- BAD: RANDOM on a UNIQUE table (not supported)
CREATE TABLE users (...) UNIQUE KEY(user_id)
DISTRIBUTED BY RANDOM BUCKETS 8;
```

**Correct:**

```sql
-- GOOD: HASH on primary key for UNIQUE
CREATE TABLE users (...) UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 8;  -- ~15 GB compressed

-- GOOD: RANDOM for DUP when no filter column is obvious
CREATE TABLE raw_logs (...) DUPLICATE KEY(log_time)
DISTRIBUTED BY RANDOM BUCKETS 3;  -- small table or full-scan workload
```

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)

---

## Choose High-Cardinality, Low-NULL Bucket Key

**Impact: HIGH — Low-cardinality keys cause uneven data distribution.**

Good bucket key properties:
1. **High cardinality** — many distinct values (user_id, order_id)
2. **Low NULL rate** — NULLs all hash to the same bucket
3. **Used in WHERE/JOIN** — enables partition pruning

**Bad choices:** status (3 values), gender (2 values), country (200 values for global data)
**Good choices:** user_id, order_id, device_id, session_id

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)

---

## Target 1-10 GB Per Tablet

**Impact: HIGH — Tablet size directly affects query parallelism and metadata overhead.**

Rules:
- **Target:** 1-10 GB per tablet (compressed)
- **Max buckets per partition:** ≤ 64
- **Preferred:** Calculate explicit bucket count: `daily_data_GB / target_tablet_GB`

```sql
-- GOOD: Explicit count from sizing math
-- 14 GB/day partition, target ~2 GB/tablet → 8 buckets
DISTRIBUTED BY HASH(user_id) BUCKETS 8

-- 3 GB/day partition, target ~1 GB/tablet → 4 buckets
DISTRIBUTED BY HASH(order_id) BUCKETS 4

-- 136 GB/day partition, target ~4 GB/tablet → 32 buckets
DISTRIBUTED BY HASH(conn_id) BUCKETS 32
```

Always write a numeric bucket count. Automatic bucket sizing obscures intent and may pick suboptimal counts; if volume is unknown, use a conservative explicit fallback such as 3, 8, 16, or 32 buckets based on expected table size.

**Warning signs:**
- Tablets < 100 MB → Too many buckets, merge or reduce
- Tablets > 20 GB → Too few buckets, increase count

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)

---

## Sort Key Rules

## Avoid FLOAT/DOUBLE in Sort Key

**Impact: HIGH — FLOAT/DOUBLE columns disable prefix index and ZoneMap pruning.**

- FLOAT and DOUBLE **cannot participate** in the prefix index
- They also **disable ZoneMap** statistics for that column
- Use DECIMAL instead for numeric precision

```sql
-- BAD: FLOAT in key breaks prefix index
DUPLICATE KEY(price, product_id)  -- price is FLOAT

-- GOOD: Use DECIMAL
CREATE TABLE products (
    product_id INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    name VARCHAR(200)
) DUPLICATE KEY(product_id, price);
```

Reference: [Prefix Index](https://doris.apache.org/docs/table-design/index/prefix-index)

---

## Cluster Key to Decouple Sort from Primary Key

**Impact: HIGH — UNIQUE tables sort data by primary key, but queries may filter on other columns.**

For UNIQUE MoW tables, the primary key determines dedup but the **Cluster Key** determines physical sort order:

```sql
CREATE TABLE users (
    user_id BIGINT NOT NULL,
    region VARCHAR(20),
    name VARCHAR(100)
) UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- ~10 GB compressed
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "cluster_key" = "region, user_id"
);
-- Dedup by user_id, but data sorted by region first (better for region-filtered queries)
```

**When to use:** When your most common WHERE clause filters on columns that are NOT your primary key.

Reference: [Cluster Key](https://doris.apache.org/docs/table-design/index/prefix-index#cluster-key)

---

## Fixed-Length Types (INT/DATE) Before VARCHAR in Key

**Impact: HIGH — A VARCHAR column terminates the prefix index.**

Prefix index rules:
- Max 3 columns OR 36 bytes (whichever comes first)
- **VARCHAR terminates the index** — only the first 20 bytes of the VARCHAR are included, and no more columns after it

```sql
-- GOOD: Fixed-length types first
DUPLICATE KEY(user_id, event_date, event_type)
--            INT(4B)  DATE(4B)    VARCHAR(→ terminates)

-- BAD: VARCHAR first wastes the prefix index
DUPLICATE KEY(event_type, user_id, event_date)
--            VARCHAR(→ terminates after 20B, user_id and event_date NOT in index)
```

Reference: [Prefix Index](https://doris.apache.org/docs/table-design/index/prefix-index)

---

## Prefix Index Limits — 3 Columns, 36 Bytes

**Impact: HIGH — Columns beyond the limit get no prefix index benefit.**

| Rule | Detail |
|------|--------|
| Max columns | 3 |
| Max bytes | 36 |
| VARCHAR | Terminates the index (only first 20 bytes included) |
| FLOAT/DOUBLE | **Cannot be in prefix index** — breaks ZoneMap too |

**Example:**

```sql
-- user_id(BIGINT=8B) + event_date(DATE=4B) + app_id(INT=4B) = 16B, 3 cols ✓
DUPLICATE KEY(user_id, event_date, app_id)

-- If you need a 4th filter column, add a separate index (BloomFilter, Inverted)
```

Reference: [Prefix Index](https://doris.apache.org/docs/table-design/index/prefix-index)

---

## High-Selectivity Columns First in Sort Key

**Impact: CRITICAL — Sort key order determines query performance through prefix index.**

Place columns in this order:
1. Most frequently filtered columns first
2. Higher selectivity (more distinct values) before lower
3. Equality filters before range filters

```sql
-- GOOD: user_id (high selectivity, common filter) first
DUPLICATE KEY(user_id, event_time, event_type)

-- BAD: event_type (low selectivity) first
DUPLICATE KEY(event_type, event_time, user_id)
```

The first 3 columns (or first 36 bytes) form the **prefix index**, which is the primary lookup structure in Doris.

Reference: [Sort Key](https://doris.apache.org/docs/table-design/index/prefix-index)

---

## Data Type Rules

## BITMAP_UNION for Exact Count-Distinct and Funnel Analysis
**Impact: HIGH — COUNT(DISTINCT col) on high-cardinality columns is extremely expensive. BITMAP gives exact results with O(1) merge.**
```sql
CREATE TABLE daily_uv (
    dt DATE NOT NULL,
    page VARCHAR(200) NOT NULL,
    uv BITMAP BITMAP_UNION
) AGGREGATE KEY(dt, page)
DISTRIBUTED BY HASH(page) BUCKETS 5;  -- ~10 GB compressed
-- Insert with to_bitmap():
INSERT INTO daily_uv SELECT '2025-01-01', '/home', to_bitmap(user_id) FROM events;
-- Query exact UV:
SELECT dt, bitmap_count(uv) AS unique_visitors FROM daily_uv GROUP BY dt;
```
**Funnel / Retention with bitmap_intersect():**
```sql
SELECT bitmap_count(bitmap_intersect(uv)) AS retained_users
FROM daily_uv WHERE dt IN ('2025-01-01', '2025-01-02');
```
**Orthogonal analysis:** Use INTERSECT_COUNT for multi-dimensional user segmentation.
Reference: [BITMAP](https://doris.apache.org/docs/sql-manual/data-types/aggregate/BITMAP)

---

## Doris-Specific Type Gotchas
**DATETIME precision:** Default DATETIME is seconds. Use `DATETIME(3)` for milliseconds, `DATETIME(6)` for microseconds.
**STRING vs VARCHAR:** STRING cannot be used as key, partition, or bucket column. Use VARCHAR for keyed columns.
**VARCHAR(65533) has identical performance to VARCHAR(255)** — Doris uses variable-length storage, so there's no penalty for a larger max. When unsure, use VARCHAR(65533).
**CHAR vs VARCHAR:** CHAR pads with spaces to fixed length. Only use CHAR for truly fixed-width codes (country_code CHAR(3)). Otherwise, prefer VARCHAR.
```sql
-- GOOD: Appropriate types
CREATE TABLE t (
    ts DATETIME(3),           -- millisecond precision
    country CHAR(3),          -- fixed 3-char code
    name VARCHAR(65533),      -- variable, no perf penalty
    big_text STRING            -- only for non-key, non-partitioned columns
);
```

---

## Use Native Types, Not STRING for Everything
**Impact: HIGH — STRING columns cannot be used as partition, bucket, or sort key columns.**
Always use the most specific type: INT for numbers, DATE/DATETIME for timestamps, DECIMAL for money.
```sql
-- BAD
CREATE TABLE t (id STRING, ts STRING, amount STRING);
-- GOOD
CREATE TABLE t (id BIGINT, ts DATETIME(3), amount DECIMAL(12,2));
```
Reference: [Data Types](https://doris.apache.org/docs/sql-manual/data-types/overview)

---

## VARIANT Type for Semi-Structured JSON Data
**Impact: HIGH — VARIANT provides columnar storage for JSON with automatic type inference.**
Use VARIANT instead of JSON or STRING for semi-structured data:
```sql
CREATE TABLE events (
    event_time DATETIME NOT NULL,
    event_id BIGINT NOT NULL,
    data VARIANT
) DUPLICATE KEY(event_time, event_id)
DISTRIBUTED BY HASH(event_id) BUCKETS 5;  -- ~10 GB compressed
-- Query nested fields directly:
SELECT data['user']['name'], data['action'] FROM events;
```
**Schema Template:** Pre-define expected fields for better columnar storage:
```sql
ALTER TABLE events SET ("variant_schema_template" = '{"user.name": "STRING", "action": "STRING", "amount": "DOUBLE"}');
```
**Inverted Index on VARIANT fields:**
```sql
ALTER TABLE events ADD INDEX idx_action(CAST(data['action'] AS VARCHAR)) USING INVERTED;
```
**MATCH search on VARIANT text fields:**
```sql
SELECT * FROM events WHERE CAST(data['message'] AS VARCHAR) MATCH 'error timeout';
```
Reference: [VARIANT Type](https://doris.apache.org/docs/sql-manual/data-types/semi-structured/VARIANT)

---

## JSON/ARRAY/Complex Types Disable ZoneMap
**Impact: HIGH — ZoneMap statistics are not generated for JSON, ARRAY, MAP, STRUCT, or STRING columns.**
ZoneMap stores min/max values per data page, enabling skip scanning. Complex types disable this optimization.
**Workaround:** Extract frequently filtered fields into dedicated columns with native types.
```sql
-- BAD: Filtering on JSON field — no ZoneMap, full scan
SELECT * FROM events WHERE payload->'$.status' = 'error';
-- GOOD: Extract to a native column
CREATE TABLE events (
    ..., status VARCHAR(20), payload JSON,
    INDEX idx_status(status) USING INVERTED
);
SELECT * FROM events WHERE status = 'error';
```

---

## Table Properties

## Properties Cloud Mode Forces
In Cloud mode (storage-compute separation):
- `replication_num` is forced to `1` (data stored in object storage)
- HASH bucketing required for UNIQUE MoW
- File cache controls performance (see `schema-cache-file-cache`)
```sql
PROPERTIES ("replication_num" = "1");
```

---

## LZ4 Default vs ZSTD for Logs/Cold Data
| Algorithm | Speed | Ratio | Use When |
|-----------|-------|-------|----------|
| LZ4 | Fastest | Lower | Default, hot data, low-latency |
| ZSTD | Slower | 2-3× better | Logs, cold data, archival |
```sql
-- For log/event tables with high redundancy:
PROPERTIES ("compression" = "zstd");
-- For hot analytical tables (default):
PROPERTIES ("compression" = "lz4");
```

---

## Index Rules

## Bitmap Index for Medium-Cardinality Dimensions (100-100K distinct values)
**Impact: MEDIUM — Efficient for columns with moderate cardinality used in filters.**
```sql
CREATE INDEX idx_city ON table_name(city) USING BITMAP;
```
**Sweet spot:** 100 to 100,000 distinct values (status codes, cities, categories).
**Restrictions:**
- Only one bitmap index can be created at a time (sequential schema change)
- `DROP INDEX` is also a schema change and takes significant time
- Only on value columns, not key columns
- Segment V2 format required

---

## BloomFilter for High-Cardinality Equality Filters
**Impact: HIGH — Skips data pages that definitely don't contain the filtered value.**
Use for columns with ≥ 5000 distinct values, filtered with `=` or `IN`.
```sql
-- Add BloomFilter index
PROPERTIES ("bloom_filter_columns" = "trace_id, session_id");
```
**Constraints:**
- NOT supported on TINYINT, FLOAT, or DOUBLE columns
- Only accelerates `=` and `IN` filters (not LIKE, not range)
- Minimum recommended cardinality: 5000+ distinct values
- False positive rate ~1% (configurable via bloom_filter_fpp)
- Do not use inline `INDEX ... USING BLOOM FILTER` in generated DDL; use the table property above.

---

## Inverted Index for Text Search and Range on Non-Key Columns
**Impact: HIGH — Enables full-text search and efficient range filters without modifying the sort key.**
```sql
-- Text search with parser
INDEX idx_body(body) USING INVERTED PROPERTIES("parser" = "unicode")
-- Equality/range on non-key column
INDEX idx_status(status) USING INVERTED
```
**Parser options:** `none` (exact), `english`, `unicode` (multilingual), `chinese` (CJK).
**Supported filter types:** `=`, `IN`, `>`, `<`, `>=`, `<=`, `MATCH_ALL`, `MATCH_ANY`, `MATCH_PHRASE`.
Reference: [Inverted Index](https://doris.apache.org/docs/table-design/index/inverted-index)

---

## NGram BloomFilter for LIKE '%pattern%' Queries
**Impact: HIGH — LIKE '%pattern%' causes full table scan without NGram index.**
```sql
INDEX idx_url(url) USING NGRAM_BF PROPERTIES("gram_size" = "3", "bf_size" = "1024")
```
The NGram BloomFilter breaks text into 3-character grams and uses a bloom filter to skip non-matching pages.
**When to use:** `LIKE '%keyword%'` queries on VARCHAR/STRING columns.
**When NOT to use:** Exact match (`=`) → use regular BloomFilter. Full-text search → use Inverted Index.
Reference: [NGram BloomFilter](https://doris.apache.org/docs/table-design/index/ngram-bloomfilter-index)

---

## Full-Text Search with MATCH Functions and BM25 Scoring
**Impact: HIGH — Enables search-engine-like text queries with relevance ranking.**
**7 MATCH operators:** MATCH_ALL, MATCH_ANY, MATCH_PHRASE, MATCH_PHRASE_PREFIX, MATCH_PHRASE_EDGE, MATCH_REGEXP, MATCH_ELEMENT_EQ.
```sql
-- Setup: Inverted index with parser
INDEX idx_content(content) USING INVERTED PROPERTIES(
    "parser" = "unicode", "support_phrase" = "true"
)
-- Queries (WHERE clause only):
WHERE content MATCH_ALL 'database analytics'    -- all terms
WHERE content MATCH_ANY 'database analytics'    -- any term
WHERE content MATCH_PHRASE 'real time analytics' -- exact phrase
```
**SEARCH() unified DSL:** Combine operators in one function:
```sql
WHERE SEARCH(content, '"real time" +analytics -legacy', 'parser=unicode')
```
**BM25 scoring:** Rank results by relevance:
```sql
SELECT doc_id, score() AS relevance FROM docs
WHERE content MATCH_ANY 'doris analytics' ORDER BY relevance DESC;
```
**Custom analyzers, hybrid text+vector search, and VARIANT text search** are all supported.
Reference: [Full-Text Search](https://doris.apache.org/docs/table-design/index/inverted-index)

---

## HNSW/IVF Vector Index for ANN Search
**Impact: HIGH — Enables approximate nearest neighbor search on embeddings.**
Requires Doris 4.0+ with vector support.
```sql
CREATE TABLE embeddings (
    doc_id BIGINT NOT NULL,
    content VARCHAR(65533),
    embedding ARRAY<FLOAT> NOT NULL
) DUPLICATE KEY(doc_id)
DISTRIBUTED BY HASH(doc_id) BUCKETS 5;  -- ~10 GB compressed
-- Add HNSW index:
CREATE INDEX idx_vec ON embeddings(embedding) USING HNSW
PROPERTIES("dim" = "768", "metric" = "cosine", "m" = "16", "ef_construction" = "200");
-- Query:
SELECT doc_id, l2_distance(embedding, [0.1, 0.2, ...]) AS dist
FROM embeddings ORDER BY dist LIMIT 10;
```
**Index types:** HNSW (fast, memory-heavy), IVF_FLAT (balanced), IVF_PQ (compressed).

---

## Materialized Views

## Async MV for Multi-Table JOIN Acceleration
**Impact: HIGH — Pre-computes JOINs so queries read a flat table instead of joining at runtime.**
```sql
CREATE MATERIALIZED VIEW mv_order_details
REFRESH AUTO ON SCHEDULE EVERY 10 MINUTE
AS SELECT o.order_id, o.amount, p.product_name, c.customer_name
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN customers c ON o.customer_id = c.customer_id;
```
**Refresh modes:** AUTO or COMPLETE with ON SCHEDULE (periodic), ON COMMIT (on base table change, limit: ≤5 updates/hr), or manual refresh.
Reference: [Async Materialized View](https://doris.apache.org/docs/query-acceleration/materialized-view/async-materialized-view)

---

## Async MV Operational Limits
| Limit | Value |
|-------|-------|
| Max rows per MV | ~50 million |
| Max JOINs | 2 |
| Max partitions | 30 |
| Max concurrent refreshes | 3 |
| Cluster resource cap | 40% |
| ON COMMIT limit | ≤ 5 updates/hour |
**Capacity estimation:** ~20-30 active async MVs on a 3-node cluster.
**Layered design pattern:** Build MVs on top of other MVs (Layer 1: base aggregations, Layer 2: cross-table joins).
**partition_sync_limit:** Focus refresh on recent data only:
```sql
CREATE MATERIALIZED VIEW mv_recent
PROPERTIES ("partition_sync_limit" = "7")
REFRESH AUTO ON SCHEDULE EVERY 1 HOUR
AS SELECT ... FROM orders ...;
```

---

## Sync MV (Rollup) for Single-Table Aggregation
**Impact: HIGH — Pre-aggregates data; optimizer rewrites queries automatically.**
```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT dt, store_id, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders GROUP BY dt, store_id;
```
**Restriction: NOT supported on UNIQUE KEY tables.** Use async MVs instead.
Sync MVs are maintained synchronously with the base table — zero lag.
Reference: [Sync Materialized View](https://doris.apache.org/docs/query-acceleration/materialized-view/sync-materialized-view)

---

## Caching Rules

## File Cache Strategies (Cloud / Storage-Compute Separation)
**Key metric: 60% of data cached locally = 95% cache hit rate.** Maintain 90%+ hit rate.
Cache modes:
- **LRU (default):** Evicts least recently used. Good for uniform access.
- **TTL:** Time-based eviction. Good for time-series with clear hot/cold boundary.
**Table-level cache control:**
```sql
-- Keep dimension tables cached forever
ALTER TABLE dim_stores SET ("file_cache_ttl_seconds" = "0");  -- 0 = never evict
-- Hot window for fact tables
ALTER TABLE fact_orders SET ("file_cache_ttl_seconds" = "604800");  -- 7 days
```
**IOPS guidance:** SSD cache: ~500 IOPS/disk. HDD: ~200 IOPS/disk.

---

## Query Cache and Partition Cache
**Query cache:** Identical SQL → instant response (no computation).
```sql
SET enable_query_cache = true;
```
**Partition cache:** Only recomputes partitions with new data. Ideal for time-series dashboards where most partitions are historical and unchanged.
```sql
SET enable_partition_cache = true;
```
**When to use:**
- Query cache: Repeated identical queries (dashboard auto-refresh)
- Partition cache: Time-series with mostly historical data

---

## Sizing Guides

## BE Sizing — Cloud / Storage-Compute Separation
In cloud mode, data is in object storage (S3/GCS). BEs only cache hot data locally.
**CPU:** Same as integrated — determines query parallelism.
**Memory:** 32-128 GB. Used for query execution, not data storage.
**Local disk:** SSD for file cache. Size based on hot data ratio (60% cached = 95% hit rate).
**Elasticity:** Can scale BE nodes independently from data volume. Add BEs for more compute, not more storage.

---

## BE Sizing — Integrated Storage Mode
In integrated mode, each BE stores data locally on disk.
**CPU:** 16-64 cores per BE. More cores = more concurrent query/scan threads.
**Memory:** 64-256 GB per BE. Rule of thumb: 4 GB RAM per 1 TB stored data.
**Disk:** SSD recommended. 1-10 TB per BE. Use RAID or multiple disks for throughput.
**Node count:** Start with 3 nodes for HA. Scale horizontally for more throughput.

---

## FE Node Sizing
| Cluster Size | FE Nodes | Memory | CPU |
|-------------|----------|--------|-----|
| Small (< 10 BE) | 1 Leader + 2 Follower | 16 GB | 8 cores |
| Medium (10-50 BE) | 1 Leader + 2 Follower | 32 GB | 16 cores |
| Large (50+ BE) | 1 Leader + 4 Follower | 64 GB | 32 cores |
FE nodes store metadata (table schemas, partitions, tablets) in memory. Scale FE memory with table count and partition count rather than data volume.

---

## Storage Calculation Formula
```
Raw data × compression ratio × replication_num = Required storage
```
**Compression ratios (typical):**
| Data Type | LZ4 Ratio | ZSTD Ratio |
|-----------|-----------|------------|
| Structured (numeric) | 3-5× | 5-8× |
| Logs/text | 5-10× | 10-20× |
| JSON/semi-structured | 3-8× | 5-12× |
**Example:** 1 TB/day raw logs × 30 days retention × ZSTD (10× compression) × 1 replica = 3 TB storage
**Include overhead:** Add 20-30% for metadata, compaction temp space, and safety margin.

---

## Getting Started

> For {{CLOUD_PRODUCT_NAME}} setup, see the `{{CLOUD_OPS_SKILL}}` skill.

## Getting Started — Self-Hosted / BYOC / On-Prem
### Prerequisites
- FE nodes: Java 8+ runtime
- BE nodes: Linux with sufficient disk, memory
- Network: FE and BE nodes must be able to communicate
### Deployment Steps
1. Deploy FE nodes (1 Leader + 2 Followers for HA)
2. Deploy BE nodes (3+ for production)
3. Register BEs with FE: `ALTER SYSTEM ADD BACKEND "<be_host>:9050";`
4. Create database and tables
### Connect
```bash
mysql -h <fe_host> -P 9030 -u root
```
### Self-Hosted Properties
```sql
PROPERTIES ("replication_num" = "3");  -- 3 replicas for HA
```
Reference: [Apache Doris Installation](https://doris.apache.org/docs/install/cluster-deployment/standard-deployment)

---
