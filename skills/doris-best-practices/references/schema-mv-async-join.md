---
title: Async MV for Multi-Table JOIN Acceleration
impact: HIGH
tags: [schema, mv, async, join, multi-table]
---
## Async MV for Multi-Table JOIN Acceleration
**Impact: HIGH — Pre-computes JOINs so queries read a flat table instead of joining at runtime.**

### Correct Syntax
```sql
CREATE MATERIALIZED VIEW mv_order_details
BUILD DEFERRED REFRESH AUTO ON SCHEDULE EVERY 1 HOUR
DISTRIBUTED BY HASH(order_id) BUCKETS 4
PROPERTIES ('compression' = 'zstd')
AS SELECT o.order_id, o.amount, p.product_name, c.customer_name
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN customers c ON o.customer_id = c.customer_id;
```
After creation, trigger first refresh: `REFRESH MATERIALIZED VIEW mv_order_details AUTO;`

### State Requirements for Query Rewrite
All must be true (check via `SELECT * FROM mv_infos('database'='db_name')`):
- `State = NORMAL` (not SCHEMA_CHANGE)
- `RefreshState = SUCCESS` (at least one successful refresh)
- `SyncWithBaseTables = 1` (or `grace_period` allows staleness)

### CRITICAL: Predicate Compensation Limitation
Auto-rewrite **works** when WHERE predicates are on **fact table columns**:
```sql
-- This WILL auto-rewrite to use the async MV:
SELECT ... FROM fact JOIN dim ON ... WHERE fact.country = 'US' GROUP BY ...
```
Auto-rewrite **fails** when WHERE predicates are on **dimension table columns** (joined columns):
```sql
-- This will NOT auto-rewrite ("Predicate compensate fail"):
SELECT ... FROM fact JOIN dim ON ... WHERE dim.name = 'Partner_X' GROUP BY ...
```
The optimizer cannot trace column lineage from `dim.name` in the query to the MV's aliased column.

### Practical Usage: Query Async MVs Directly
Since most BI queries filter on dimension columns (partner name, account name), the reliable approach is to **query the async MV directly** as a pre-built mart table:
```sql
-- Instead of 3-table JOIN:
SELECT date, SUM(revenue) FROM fact f
  JOIN dim_conn c ON f.conn_id = c.id
  JOIN dim_sf sf ON c.acct_id = sf.acct_id
  WHERE sf.partner_name = 'X' GROUP BY 1;

-- Query the async MV directly (8,000x less I/O):
SELECT date, SUM(revenue) FROM mv_fact_partner
  WHERE partner_name = 'X' GROUP BY 1;
```

### Session Variables
| Variable | Default | Purpose |
|---|---|---|
| `enable_materialized_view_rewrite` | `true` | Master switch for async MV rewrite |
| `materialized_view_rewrite_success_candidate_num` | `3` | Max rewrite candidates for CBO |

Reference: [Async Materialized View](https://doris.apache.org/docs/query-acceleration/materialized-view/async-materialized-view)
