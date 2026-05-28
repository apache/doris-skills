---
title: BITMAP_UNION for Exact Count-Distinct
impact: HIGH
tags: [schema, types, bitmap, count-distinct, funnel, retention]
---
## BITMAP_UNION for Exact Count-Distinct and Funnel Analysis
**Impact: HIGH — COUNT(DISTINCT col) on high-cardinality columns is extremely expensive. BITMAP gives exact results with O(1) merge.**
```sql
CREATE TABLE daily_uv (
    dt DATE NOT NULL,
    page VARCHAR(200) NOT NULL,
    uv BITMAP BITMAP_UNION
) AGGREGATE KEY(dt, page)
DISTRIBUTED BY HASH(page) BUCKETS 5;  -- calculate: data_per_partition_GB × compression / 2
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
