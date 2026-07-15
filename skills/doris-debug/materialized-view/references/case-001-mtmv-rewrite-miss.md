# Case: Async MTMV refresh succeeds but query rewrite never matches

## Symptom

`mv_infos()` shows `RefreshState = SUCCESS`, but `EXPLAIN SELECT` on the base table never shows `MATERIALIZED_REWRITE`. Query always scans base table.

## Root cause

MTMV rewrite has strict preconditions that aren't surfaced well:
1. `mv.properties("partition_sync")` must be enabled for partitioned tables, or the MV partitions don't align
2. The SELECT must be an exact match or a CBO-provable subset of the MV definition
3. If the MV uses aggregation, the query must select at the MV's aggregation granularity
4. `enable_materialized_view_rewrite` session var must be true (default true, but check)

## Fix direction

```sql
-- 1. Check MV state (not just RefreshState — check all columns)
SELECT * FROM mv_infos('database'='db') WHERE Name='mv'\G

-- 2. Check rewrite eligibility
EXPLAIN VERBOSE SELECT ...;  -- look for "mv=... matched=false" in output

-- 3. Ensure rewrite switch is on
SET enable_materialized_view_rewrite = true;

-- 4. For partition alignment
ALTER MATERIALIZED VIEW mv SET ("partition_sync" = "true");
REFRESH MATERIALIZED VIEW mv COMPLETE;

-- 5. Check if the query's WHERE clause can be satisfied
--    If MV filters on col_a but query filters on col_b, rewrite won't match
```

Source: `fe/.../mtmv/MTMVService.java` rewrite rules, `fe/.../materializedview/MaterializedViewRewriter.java`.
