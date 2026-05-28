---
title: Dynamic Partition for Automated Data Lifecycle
impact: HIGH
impactDescription: "Without dynamic partition, old data accumulates and manual cleanup is error-prone"
tags: [schema, partition, dynamic, ttl, lifecycle]
---

## Dynamic Partition for Automated Data Lifecycle

**Impact: HIGH — Automates partition creation and TTL-based data cleanup.**

Key properties:
- `time_unit`: DAY, WEEK, MONTH
- `start`: Negative number = how many units to keep (TTL). E.g., `"-7"` keeps 7 days.
- `end`: Positive number = how many future partitions to pre-create
- Bucket count belongs in `DISTRIBUTED BY ... BUCKETS N`, not in dynamic partition properties.

```sql
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);
```

**Warnings:**
- Do not use dynamic partition for tables with < 20 million rows. Creates wasteful empty partitions.
- **Do NOT combine with AUTO PARTITION.** If using `AUTO PARTITION BY RANGE`, do not add `dynamic_partition.*` properties — they are redundant and conflict. AUTO PARTITION handles partition creation on data arrival. For TTL cleanup, use a scheduled `ALTER TABLE ... DROP PARTITION` job instead.

Reference: [Dynamic Partition](https://doris.apache.org/docs/table-design/data-partitioning/dynamic-partitioning)
