---
title: Target 1-10 GB Per Tablet
impact: HIGH
impactDescription: "Too many small tablets waste metadata; too few large tablets limit parallelism"
tags: [schema, bucket, tablet, size, auto]
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
- Tablets < 100 MB → Too many buckets, reduce count
- Tablets > 20 GB → Too few buckets, increase count

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)
