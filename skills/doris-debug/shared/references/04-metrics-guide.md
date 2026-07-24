# Doris Key Monitoring Metrics Quick Reference (Per-Domain Metrics Guide)

> Metric meanings, collection methods, and alert thresholds organized by diagnostic domain.

## Query Execution Metrics

### FE Side

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `QueryTime` | `fe.audit.log` | End-to-end latency (ms) | > 30s |
| `ScanRows` | `fe.audit.log` | Rows scanned | > 1B (watch for scan amplification) |
| `ScanBytes` | `fe.audit.log` | Bytes scanned | > 10GB (full table scan risk) |
| `Plan Time` | Profile | FE planning time | > 1s (check Nereids/CBO) |
| `Nereids Translate Time` | Profile | Nereids translation time | > 1s |
| `Create Scan Range Time` | Profile | Time to create scan ranges | > 5s (check external table RPCs) |
| `ExecTime` | Profile per-operator | Execution time of each operator | Single operator > 50% total |

### BE Side

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `WaitForData` | Profile exchange operator | Time waiting for upstream exchange data | ≈ query timeout → brpc problem |
| `ScannerGetBlockTime` | Profile scan operator | Time spent reading blocks during scan | > 50% ExecTime → IO bottleneck |
| `SpillDataSize` | Profile | Amount of data spilled to disk | > 0 → memory pressure |
| `JoinProbeTime` | Profile join operator | Hash join probe time | > 30% ExecTime → join bottleneck |
| `FragmentInstanceNum` | Profile / be/log | Number of fragment instances | > 1000 → excessive concurrency |

```sql
SET enable_profile = true;
-- After running the query, fetch the Profile via FE HTTP:
curl -s "http://$FE:8030/api/query_profile?query_id=$QID"
```

## Compaction Metrics

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `tablet_base_max_compaction_score` | BE /metrics | Max base score | > 100 |
| `tablet_cumulative_max_compaction_score` | BE /metrics | Max cumu score | > 50 |
| `compaction_bytes_total` | BE /metrics | Compaction write bytes/s | Near disk bandwidth → disk bottleneck |
| `version_count` | `SHOW TABLET` | Number of tablet versions | > 1800 → approaching max (2000) |
| `CloneTaskQueue` | `SHOW PROC '/tasks'` | Clone task backlog | > 50 |

```bash
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep compaction --warn
```

**Distinguishing Base vs Cumulative**:
- `type=1` = BASE_COMPACTION → base score; the problem direction is base rowset merging
- `type=2` = CUMULATIVE_COMPACTION → cumu score; the problem direction is write frequency

## Node Memory Metrics

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `process_mem_usage` | BE /metrics or `/profile` | BE process RSS | > 85% mem_limit |
| `MemTrackerLimiter` | `be.WARNING` | Memory tracker limit exceeded | Any occurrence → memory pressure |
| `jemalloc_retained_bytes` | BE /metrics | Memory retained by jemalloc and not returned to the OS | > 5GB → severe fragmentation |
| `DataPageCache[size]` | `/profile` | DataPageCache size | Evaluate together with RSS |
| `SegmentCache[size]` | `/profile` | SegmentCache size | Evaluate together with RSS |
| `QueryCache@cache` | `/profile` | QueryCache size | > 20% mem_limit → consider reducing |
| `file_cache_need_update_lru_blocks_length` | BE bvar | FileCache LRU queue length | > 100000 → possible backlog |

```bash
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep "memory|jemalloc|cache" --warn
```

**RSS vs MemTracker Gap**:
- jemalloc arena fragmentation: 10-20% overhead
- brpc buffer pools: not tracked by MemTracker
- Thread stacks: ~8MB × thread count
- In practice: set `mem_limit` to 60-70% of system RAM to leave room for overhead

## Import Metrics

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `LoadTime` | `SHOW LOAD` | Total load time | > 10min (except large tables) |
| `publish_timeout` | be/log | Version publish timeout | Any occurrence → compaction or tablet count problem |
| `wal_size` | `wal-du` command | WAL disk usage | > 50% of disk → consumption cannot keep up |
| `group_commit_insert_threads` | be.conf | Commit worker pool size | Busy rate > 80% |
| `heavy_work_pool_active` | BE bvar | Active threads in the heavy pool | = max → possible queuing |

```bash
./scripts/doris-debug wal-du /path/to/be/storage
./scripts/doris-debug log-grep be/log --pack group_commit
```

## Cloud Storage-Compute Separation Metrics

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `file_cache_hit_ratio` | BE /metrics | Local cache hit ratio | < 50% → poor cache effectiveness |
| `s3_read_bytes_total` | BE /metrics | S3 read bytes (on cache miss) | Persistently high → cache miss or insufficient warmup |
| `meta_service_rpc_latency` | FE logs or monitoring | meta-service RPC latency | P99 > 100ms |
| `compute_group_fragment_num` | FE cloud cluster check | Fragment concurrency per compute group | > 2000 → excessive concurrency |
| `file_cache_size` | BE /metrics | Current file cache usage | Near total_size configured in file_cache_path → consider expanding |

```bash
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep "file_cache|s3"
```

## Resource Isolation Metrics

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `ActiveQueries` | `SHOW WORKLOAD GROUPS` | Currently active queries | = max_concurrency |
| `QueuedQueries` | `SHOW WORKLOAD GROUPS` | Number of queued queries | > 0 persistently → queue saturated |
| `QueueTime` | Profile | Query queuing time | > 30s |
| `cpu_hard_limit` | cgroup | CPU hard limit | Usage > 90% |
| `memory_limit_bytes` | cgroup | cgroup memory limit | RSS > 85% |

```sql
SHOW WORKLOAD GROUPS\G
SELECT * FROM information_schema.workload_group_resource_usage;
```

```bash
cat /sys/fs/cgroup/cpu/doris/<wg_id>/cpu.shares
cat /sys/fs/cgroup/memory/doris/<wg_id>/memory.limit_in_bytes
```

## FE Health

| Metric | Source | Meaning | Alert Threshold |
|------|------|------|----------|
| `Old Gen usage` | `jmap -heap` | FE JVM Old Gen usage | > 85% → approaching OOM |
| `GC time` | `fe.gc.log` | GC time | Full GC > 10s per run |
| `number_of_queries` | `SHOW PROC '/current_queries'` | Currently running queries | > 1000 |
| `BDBJE log file count` | `ls fe/doris-meta/bdb/*.jdb \| wc -l` | Number of BDBJE log files | Abnormal growth → possible disk problem |
| `Edit log replay gap` | `SHOW FRONTENDS` → `ReplayedJournalId` | Log replay lag from Master | > 1000 |

```bash
jstack <fe_pid> | grep -A5 "BLOCKED\|WAITING" | head -30
jmap -heap <fe_pid> 2>/dev/null | grep "Old\\|Eden"
```
