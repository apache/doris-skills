---
title: "Use Case: Dashboard / Pre-Aggregated Metrics"
impact: CRITICAL
tags: [usecase, dashboard, metrics, aggregate, rollup, bi]
---
## Use Case: Dashboard / Pre-Aggregated Metrics
For pre-computing dashboard numbers: daily sales, ad click totals, user activity summaries.
### Template
```sql
CREATE TABLE daily_sales_metrics (
    dt DATE NOT NULL, store_id INT NOT NULL,
    total_revenue DECIMAL(15,2) SUM DEFAULT "0",
    max_transaction DECIMAL(15,2) MAX DEFAULT "0",
    order_count BIGINT SUM DEFAULT "0",
    unique_buyers BITMAP BITMAP_UNION
) ENGINE=OLAP AGGREGATE KEY(dt, store_id)
PARTITION BY RANGE(dt) ()
DISTRIBUTED BY HASH(store_id) BUCKETS 5  -- pre-aggregated metrics: calculate: data_per_partition_GB × compression / 2
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="MONTH",
    "dynamic_partition.start"="-12","dynamic_partition.end"="1","dynamic_partition.prefix"="p");
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | AGGREGATE | Values auto-aggregate (SUM, MAX, BITMAP_UNION) on ingestion. |
| **BITMAP** | `BITMAP_UNION` for unique_buyers | Exact count-distinct without storing raw user IDs. |
### Anti-Pattern
```sql
-- BAD: Using DUPLICATE for dashboard data you'll always aggregate
CREATE TABLE daily_sales_metrics (dt DATE, store_id INT, revenue DECIMAL(15,2))
DUPLICATE KEY(dt, store_id);
-- Every query must re-aggregate billions of rows at query time.
```
