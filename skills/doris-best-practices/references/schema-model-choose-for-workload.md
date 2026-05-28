---
title: Choose Data Model for Workload
impact: CRITICAL
impactDescription: "Data model is irreversible after table creation"
tags: [schema, model, duplicate, unique, aggregate]
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
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- calculate: data_per_partition_GB × compression / 2
PROPERTIES ("enable_unique_key_merge_on_write" = "true");
```

Reference: [Data Model Overview](https://doris.apache.org/docs/table-design/data-model/overview)
