---
name: doris-debug-materialized-view
description: >
  Use for Doris sync MV (rollup) miss or async MTMV refresh/rewrite issues.
  Commands: SHOW ALTER TABLE MATERIALIZED VIEW, mv_infos(), EXPLAIN, REFRESH MATERIALIZED VIEW.
version: 0.2.0
category: materialized-view
---

# Materialized View

## Kind comparison

| Kind | Code area | Check | Rewrite mechanism |
|------|-----------|-------|-------------------|
| Sync | `MaterializedViewHandler` / rollup | `SHOW ALTER TABLE MATERIALIZED VIEW` | Transparent — planner auto-selects |
| Async MTMV | `fe/.../mtmv/` | `mv_infos()` RefreshState | CBO-based — EXPLAIN shows if matched |

## Causes

| ID | Cause | Evidence | Kind |
|----|-------|----------|------|
| A | Sync MV build pending/stuck | `SHOW ALTER TABLE MATERIALIZED VIEW` State≠FINISHED | Sync |
| B | MTMV refresh failed | `mv_infos()` RefreshState=FAIL | Async |
| C | MTMV rewrite miss | EXPLAIN shows no MATERIALIZED_REWRITE | Async |
| D | MTMV data stale | `mv_infos()` LastRefreshTime old | Async |
| E | MV not selected by planner | EXPLAIN shows TABLE SCAN not MATERIALIZED | Either |

## 10 min triage

```sql
-- Sync MV status
SHOW ALTER TABLE MATERIALIZED VIEW FROM db;

-- Async MTMV status
SELECT * FROM mv_infos('database'='db') WHERE Name='mv'\G

-- Check rewrite eligibility
EXPLAIN VERBOSE SELECT ...;

-- Force refresh
REFRESH MATERIALIZED VIEW mv;

-- Enable external MV rewrite (for catalog queries)
SET materialized_view_rewrite_enable_contain_external_table = true;
```

## Cause C — MTMV rewrite miss

Common reasons (see `fe/.../mtmv/MTMVService.java` rewrite matcher):

1. **Partition misalignment**: MV has `partition_sync=false` and query partition doesn't match → `ALTER MATERIALIZED VIEW mv SET ("partition_sync" = "true")`
2. **Aggregation granularity**: MV groups by `(a, b)` but query groups by `(a)` only → MV is not a valid rewrite target
3. **Filter mismatch**: MV WHERE clause doesn't cover query WHERE clause → check MV definition
4. **Session var off**: `SET enable_materialized_view_rewrite = true`

```sql
-- Debug: force the optimizer to log MV matching
SET enable_materialized_view_rewrite_debug_log = true;
EXPLAIN VERBOSE SELECT ...;  -- check fe/log/fe.audit.log for MV match details
```

## Cause A — Sync MV stuck

```sql
-- Cancel stuck build
CANCEL ALTER TABLE MATERIALIZED VIEW FROM db ON table;

-- Check BE compaction queue (MV build competes with compaction)
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep compaction
```

## Source

- `fe/.../mtmv/MTMVService.java` — MTMV lifecycle
- `fe/.../alter/MaterializedViewHandler.java` — sync MV alter
- `fe/.../materializedview/MaterializedViewRewriter.java` — rewrite logic
- `SessionVariable.java` — `enable_materialized_view_rewrite`, `materialized_view_rewrite_enable_contain_external_table`
