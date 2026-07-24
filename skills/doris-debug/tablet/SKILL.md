---
name: doris-debug-tablet
description: >
  Use for Doris tablet/replica health, version skew, clone backlog, disk balance,
  and tablet repair. Commands: SHOW PROC tablet_health, SHOW TABLET, ADMIN REPAIR.
version: 0.2.0
category: tablet
---

# Tablet & Replica

## Quick scan

```sql
SHOW PROC '/cluster_health/tablet_health';
SHOW PROC '/statistic';
SHOW PROC '/tasks';
```

## Causes

| ID | Cause | Evidence | Source anchor |
|----|-------|----------|---------------|
| A | Replica missing / unhealthy | `SHOW PROC '/cluster_health/tablet_health'` Health≠TOTAL | `TabletHealth.java` |
| B | Version skew | tablet version lag > 3 behind quorum | `TabletInvertedIndex.cpp` |
| C | Clone backlog | `SHOW PROC '/tasks'` CLONE queue depth > 50 | `CloneTask.cpp`, BE `clone_worker_count` |
| D | Disk skew | `SHOW PROC '/statistic'` one disk > 85% while others < 50% | `DiskBalancer` / balance config |
| E | Single tablet too large | tablet size > `compaction_tablet_size_threshold` | `config.cpp` + compaction |

## 10 min triage

```sql
-- 1. Global health snapshot
SHOW PROC '/cluster_health/tablet_health';

-- 2. Per-table replica drilldown
ADMIN SHOW REPLICA STATUS FROM db.table WHERE ReplicaStatus != 'OK';

-- 3. Task queue depth
SHOW PROC '/tasks';
```

```bash
# BE-side tablet count & version lag
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep "tablet|version|clone"
./scripts/doris-debug log-grep be/log --pack versions

# Check specific tablet distribution
curl -s "http://$FE:8030/api/tablets_distribution?db=db_name&table=tbl_name"
```

## Cause A — Replica missing

```sql
-- Identify unhealthy replicas
ADMIN SHOW REPLICA STATUS FROM db.table WHERE ReplicaStatus != 'OK';

-- Repair with low priority (production safe)
ADMIN REPAIR TABLE db.table PRIORITY = 'LOW';

-- For urgent single-tablet repair
ADMIN REPAIR TABLE db.table PARTITION (p202401) PRIORITY = 'HIGH';
```

Check BE `heartbeat_service_mgr.cpp` — heartbeats from a BE with missing tablets won't self-heal if compaction or clone threads are exhausted.

## Cause C — Clone backlog

Clone concurrency: `clone_worker_count` (default 3 in `config.cpp`). A high Clone backlog often means:

1. Tablet migration triggered by `balance_load_disk_safe_threshold` / `storage_high_watermark_usage_percent`
2. Clone threads can't keep up with the repair plan

```properties
# be.conf — raise clone workers cautiously
clone_worker_count = 6
```

## Cause D — Disk skew

```sql
SHOW PROC '/statistic';          -- per-disk usage
SHOW PROC '/backends';           -- per-BE disk UsedPct
```

```properties
# fe.conf
balance_load_disk_safe_threshold = 0.5
storage_high_watermark_usage_percent = 80
```

Manual rebalance: `ADMIN SET FRONTEND CONFIG ("disable_balance" = "true");` then selective `ADMIN REBALANCE DISK`.

## Source

- `fe/.../master/TabletHealth.java` — cluster_health proc
- `fe/.../clone/TabletSchedCtx.java`
- `be/src/agent/task_worker_pool.cpp` — clone worker pool
- `be/src/common/config.cpp` — `clone_worker_count`, `storage_root_path`
- `be/src/olap/tablet_manager.cpp` — tablet version tracking
