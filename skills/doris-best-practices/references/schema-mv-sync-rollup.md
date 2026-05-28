---
title: Sync MV (Rollup) for Single-Table Aggregation
impact: HIGH
tags: [schema, mv, sync, rollup, aggregation]
---
## Sync MV (Rollup) for Single-Table Aggregation
**Impact: HIGH — Pre-aggregates data; optimizer rewrites queries automatically. Zero lag.**

### Restrictions
- **Single-table only.** JOINs, HAVING, LIMIT, LATERAL VIEW are NOT supported. For JOINs use async MVs.
- **NOT supported on UNIQUE KEY tables.** Use async MVs instead.
- **Column aliases must be unique** and must NOT collide with any base table column name. Use prefixes (e.g., `mv_`, `pa_`).

### CRITICAL: Use Raw Columns, Not Derived Expressions
Doris does **structural matching** — `date_trunc(event_time, 'day')` in the MV will NOT match `DATE_FORMAT(event_time, '%Y-%m-%d')` in a query. They are different functions.

Store **raw columns** in the MV GROUP BY. The optimizer can then derive ANY function on top:
```sql
-- GOOD: raw event_time — matches DATE_FORMAT, HOUR, WEEKDAY, date_trunc, etc.
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT event_time AS mv_time, store_id AS mv_store, country AS mv_country,
       SUM(amount) AS mv_amount, SUM(qty) AS mv_qty
FROM orders GROUP BY mv_time, mv_store, mv_country;

-- BAD: date_trunc — only matches queries that also use date_trunc, nothing else
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT date_trunc(event_time, 'day') AS mv_date, ...
```

### Matching Rules
The optimizer auto-rewrites when:
1. Query's GROUP BY columns are a **subset** of the MV's GROUP BY columns
2. Query's aggregate functions (SUM, COUNT, MIN, MAX) exist in the MV
3. Query expressions are **derived from** MV columns (e.g., `DATE_FORMAT(mv_time, ...)` derives from `event_time`)

Reference: [Sync Materialized View](https://doris.apache.org/docs/query-acceleration/materialized-view/sync-materialized-view)
