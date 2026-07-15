---
name: doris-debug-resource-isolation
description: >
  Use for Doris Workload Group / resource tag queue starvation, CPU/memory isolation
  leaks, and workload policy debugging. Commands: SHOW WORKLOAD GROUPS, EXPLAIN resource.
version: 0.2.0
category: resource-isolation
---

# Resource Isolation (Workload Group)

## Causes

| ID | Cause | Evidence | Source anchor |
|----|-------|----------|---------------|
| A | Queue starvation | Queries queued in `SHOW WORKLOAD GROUPS`; `QueueTime` growing | `WorkloadGroupMgr.java` |
| B | CPU oversubscription | One WG consuming >90% CPU despite limits | `CgroupCpuCtl.cpp` |
| C | Memory leak across groups | MemTracker shows one WG exceeding `memory_limit` | `WorkloadGroupMemMgr.cpp` |
| D | Tag routing wrong | Query hits wrong BE set; ResourceTag mismatch | `ResourceTag.java`, `Tag.java` |
| E | WG not active / cgroup missing | `CREATE WORKLOAD GROUP` had no effect | `WorkloadGroupMgr.cpp` cgroup init |

## 10 min triage

```sql
-- Workload group status
SHOW WORKLOAD GROUPS\G
-- Check columns: Id, Name, ActiveQueries, QueuedQueries, CpuShares, MemoryLimit

-- Which WG is my query in?
SELECT * FROM information_schema.workload_group_resource_usage;

-- Workload policies (routing rules)
SHOW WORKLOAD POLICY\G
```

```bash
# BE cgroup inspection
cat /sys/fs/cgroup/cpu/doris/<wg_id>/cpu.shares
cat /sys/fs/cgroup/memory/doris/<wg_id>/memory.limit_in_bytes

./scripts/doris-debug be-metrics --be http://$BE:8040 --grep "workload_group"
```

## Cause A — Queue starvation

```sql
-- See who's queued
SHOW WORKLOAD GROUPS\G

-- Raise queue concurrency
ALTER WORKLOAD GROUP etl_wg SET (
    "max_concurrency" = "8",
    "max_queue_size" = "100",
    "queue_timeout" = "300"
);
```

Check `be/src/pipeline/task_scheduler.cpp` — the pipeline scheduler respects cgroup shares; if a high-share WG starves a low-share one, the low-share WG's queue backs up.

## Cause B — CPU oversubscription

```sql
-- Create a hard CPU cap
ALTER WORKLOAD GROUP report_wg SET (
    "cpu_share" = "1024",
    "cpu_hard_limit" = "200%"   -- 2 cores max
);

-- Force query into specific WG
SET workload_group = 'report_wg';
```

cgroup v1 vs v2 behavior differs. Confirm which is active on BE hosts:
```bash
mount | grep cgroup
ls /sys/fs/cgroup/cpu/doris/   # cgroup v1
ls /sys/fs/cgroup/doris/       # cgroup v2
```

## Cause D — Tag routing

```sql
-- Check BE tags
SHOW BACKENDS\G  -- look at Tag column

-- Check WG tag constraint
SHOW WORKLOAD GROUPS\G  -- look at ResourceTag
```

If a workload group specifies a tag but no BEs carry that tag, queries queue forever. Fix:
```sql
ALTER SYSTEM MODIFY BACKEND "host:9050" SET ("tag.tag.location" = "high_mem");
```

## Enabling cgroup on BE

```properties
# be.conf
doris_cgroup_cpu_path = /sys/fs/cgroup/cpu/doris
enable_workload_group = true
```

Without cgroup configured, `cpu_share` is a cooperative hint, not a hard guarantee.

## Source

- `be/src/common/config.cpp` — `enable_workload_group`, cgroup paths
- `be/src/pipeline/task_scheduler.cpp` — pipeline scheduling
- `fe/.../workloadgroup/WorkloadGroupMgr.java` — WG lifecycle
- `fe/.../resource/Tag.java` — resource tags
- `be/src/util/cgroup_util.cpp` — cgroup v1/v2 adapter
