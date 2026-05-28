---
title: Skip Partitioning for Small Tables
impact: HIGH
impactDescription: "Partitioning tables under 1GB adds overhead without benefit"
tags: [schema, partition, small, dimension]
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
