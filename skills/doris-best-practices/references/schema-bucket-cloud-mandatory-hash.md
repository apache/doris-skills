---
title: Cloud Mode Requires HASH Bucketing for MoW
impact: HIGH
impactDescription: "Cloud mode with UNIQUE MoW fails if RANDOM bucketing is used"
tags: [schema, bucket, cloud, mow, hash]
---

## Cloud Mode Requires HASH Bucketing for MoW

**Impact: HIGH — UNIQUE MoW tables in cloud mode must use HASH bucketing.**

In Cloud mode (storage-compute separation), RANDOM bucketing is not supported for UNIQUE KEY tables with MoW enabled.

```sql
-- GOOD: Cloud MoW with HASH
CREATE TABLE users (...)
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- cloud MoW: calculate: data_per_partition_GB × compression / 2
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "replication_num" = "1"  -- cloud mode
);
```

