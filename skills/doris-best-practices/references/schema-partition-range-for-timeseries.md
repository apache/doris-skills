---
title: RANGE Partition on Time Column for Time-Series
impact: CRITICAL
impactDescription: "Partition key is irreversible; wrong choice prevents pruning and TTL"
tags: [schema, partition, range, time-series, pruning]
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
DISTRIBUTED BY HASH(user_id) BUCKETS 10;  -- calculate: data_per_partition_GB × compression / 2
-- Every query scans ALL data, no TTL possible
```

**Correct:**

```sql
CREATE TABLE events (
    event_time DATETIME NOT NULL, user_id BIGINT, data STRING
) DUPLICATE KEY(event_time, user_id)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(user_id) BUCKETS 10  -- time-series: calculate: data_per_partition_GB × compression / 2
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);
```

**CRITICAL CONSTRAINT for UNIQUE KEY (MoW) tables:**
The partition column MUST be included in the UNIQUE KEY. Otherwise CREATE TABLE fails with "Merge-on-Write table's partition column must be KEY column".

```sql
-- BAD: partition column not in key
UNIQUE KEY(trade_id)
PARTITION BY RANGE(trade_time)  -- ERROR: trade_time not in key

-- GOOD: include partition column in key
UNIQUE KEY(trade_id, trade_time)
PARTITION BY RANGE(trade_time)  -- OK
```

Reference: [Range Partition](https://doris.apache.org/docs/table-design/data-partitioning/range-partitioning)
