---
title: Cluster Key to Decouple Sort from Primary Key
impact: HIGH
impactDescription: "UNIQUE tables sort by PK; Cluster Key lets you optimize scan order separately"
tags: [schema, keys, cluster-key, mow, sort]
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
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- calculate: data_per_partition_GB × compression / 2
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "cluster_key" = "region, user_id"
);
-- Dedup by user_id, but data sorted by region first (better for region-filtered queries)
```

**When to use:** When your most common WHERE clause filters on columns that are NOT your primary key.

Reference: [Cluster Key](https://doris.apache.org/docs/table-design/index/prefix-index#cluster-key)
