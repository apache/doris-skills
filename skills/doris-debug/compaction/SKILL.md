---
name: doris-debug-compaction
description: >
  Use for Doris -235 / too many versions and compaction lag. Error raised in
  RowsetBuilder::check_tablet_version_count when version_count > max_tablet_version_num
  (default 2000) or meta serialize size limit.
version: 0.2.0
category: compaction
---

# Compaction / Versions

## Code

`be/src/storage/rowset_builder.cpp`:

- `version_count > max_version_config` → `Status::Error<TOO_MANY_VERSION>(...)`
- Suggests reduce load frequency or raise `max_tablet_version_num` /
  `time_series_max_tablet_version_num` in `be.conf`
- Near limit triggers cumulative compaction submit

Defaults (`config.cpp`): `max_tablet_version_num=2000`, `time_series_max_tablet_version_num=20000`.

## Causes

| ID | Cause | Evidence | Fix direction |
|----|-------|----------|---------------|
| A | Ingest rate > compaction throughput | version_count rising; compaction score growing | Reduce ingest frequency or increase compaction threads |
| B | Disk IO bottleneck | `iostat` shows disk util > 90% | Move WAL to separate disk; add compaction disks |
| C | max_tablet_version_num too low for workload | -235 on normal ingest rates | Raise limit (temporary), then fix root cause |
| D | Single-tablet hotspot | One tablet has 10× versions of peers | Partition / bucket key skew |

## Actions

1. Confirm with `./scripts/doris-debug log-grep be/log --pack versions`
2. Check compaction throughput: `./scripts/doris-debug be-metrics --be http://$BE:8040 --grep compaction`
3. Check disk IO: `iostat -x 1`
4. Slow ingest / enlarge group commit batches
5. Raising `max_tablet_version_num` is a temporary valve — fix ingest vs compaction balance

```bash
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep compaction
```

## Compaction knobs

```properties
# be.conf
max_tablet_version_num = 2000               # hard cap, raise only as stopgap
time_series_max_tablet_version_num = 20000   # separate cap for time-series tables
max_cumulative_compaction_threads = -1       # -1 = auto based on CPU cores
compaction_task_num_per_disk = 4             # per-disk concurrent compaction tasks
compaction_tablet_size_threshold = 107374182400  # 100GB — above this, skip base compaction
```

## Source

- `be/src/storage/rowset_builder.cpp` — `-235` error
- `be/src/common/config.cpp` — all compaction config defaults
- `be/src/olap/cumulative_compaction_policy.cpp` — score calculation
