---
title: HASH Bucket for Pruning; RANDOM Only for DUP Full-Scans
impact: CRITICAL
impactDescription: "Bucket key is irreversible; wrong choice prevents query pruning"
tags: [schema, bucket, hash, random, pruning]
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
DISTRIBUTED BY HASH(user_id) BUCKETS 8;  -- calculate: data_per_partition_GB × compression / 2

-- GOOD: RANDOM for DUP when no filter column is obvious
CREATE TABLE raw_logs (...) DUPLICATE KEY(log_time)
DISTRIBUTED BY RANDOM BUCKETS 3;  -- small table or full-scan workload
```

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)
