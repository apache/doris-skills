---
title: Async MV Operational Limits
impact: HIGH
tags: [schema, mv, async, limits, capacity]
---
## Async MV Operational Limits
| Limit | Value |
|-------|-------|
| Max rows per MV | ~50 million |
| Max JOINs | 2 |
| Max partitions | 30 |
| Max concurrent refreshes | 3 |
| Cluster resource cap | 40% |
| ON COMMIT limit | ≤ 5 updates/hour |
**Capacity estimation:** ~20-30 active async MVs on a 3-node cluster.
**Layered design pattern:** Build MVs on top of other MVs (Layer 1: base aggregations, Layer 2: cross-table joins).
**partition_sync_limit:** Focus refresh on recent data only:
```sql
CREATE MATERIALIZED VIEW mv_recent
BUILD DEFERRED REFRESH AUTO ON SCHEDULE EVERY 1 HOUR
PROPERTIES ("partition_sync_limit" = "7")
AS SELECT ... FROM orders ...;
```

### Diagnostic Checklist (when async MV rewrite not working)
1. `SELECT Name, State, RefreshState, SyncWithBaseTables FROM mv_infos('database'='db_name')` — State must be NORMAL, RefreshState SUCCESS
2. `EXPLAIN <query>` — check `MaterializedViewRewriteFail` section at bottom
3. `"View struct info is invalid"` — benign; read the error AFTER it for the real cause
4. `"Predicate compensate fail"` — WHERE on dimension column; query the MV directly instead
5. `"The graph logic between query and view is not consistent"` — JOIN type or table order mismatch
6. `SHOW VARIABLES LIKE '%materialized_view%'` — verify `enable_materialized_view_rewrite = true`
