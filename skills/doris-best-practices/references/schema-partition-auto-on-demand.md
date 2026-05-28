---
title: AUTO PARTITION for Sporadic Data
impact: HIGH
impactDescription: "Creates partitions on-demand when data arrives, avoiding empty partitions"
tags: [schema, partition, auto, on-demand, sporadic]
---

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
DISTRIBUTED BY HASH(user_id) BUCKETS 5;  -- sporadic events: calculate: data_per_partition_GB × compression / 2
```

**When to use AUTO vs DYNAMIC:**
- **Auto:** Preferred for most cases — creates partitions on data arrival, no empty partitions
- **Dynamic:** Only when you need TTL-based auto-deletion of old partitions AND data arrives predictably every period

**WARNING: Do NOT combine AUTO PARTITION with dynamic_partition properties.** They are redundant and conflict:
- AUTO PARTITION already creates partitions on arrival — `dynamic_partition.end` (pre-creation) is unnecessary
- `dynamic_partition.prefix` conflicts with AUTO's naming scheme
- If you need old partition cleanup, use a scheduled `ALTER TABLE ... DROP PARTITION` job instead

Reference: [Auto Partition](https://doris.apache.org/docs/table-design/data-partitioning/auto-partitioning)
