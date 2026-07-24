# Doris 关键监控指标速查（Per-Domain Metrics Guide）

> 按诊断域分类的指标含义、获取方式和告警阈值。

## Query 执行指标

### FE 侧

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `QueryTime` | `fe.audit.log` | 端到端耗时 (ms) | > 30s |
| `ScanRows` | `fe.audit.log` | 扫描行数 | > 1B（关注扫描放大） |
| `ScanBytes` | `fe.audit.log` | 扫描字节数 | > 10GB（全表扫描风险） |
| `Plan Time` | Profile | FE 规划耗时 | > 1s（关注 Nereids/CBO） |
| `Nereids Translate Time` | Profile | Nereids 转译耗时 | > 1s |
| `Create Scan Range Time` | Profile | 创建 scan range | > 5s（关注外表 RPC） |
| `ExecTime` | Profile per-operator | 每个 operator 的执行耗时 | 单 operator > 50% total |

### BE 侧

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `WaitForData` | Profile exchange operator | 等待上游 exchange 数据 | ≈ query timeout → brpc 问题 |
| `ScannerGetBlockTime` | Profile scan operator | 扫描读 block 耗时 | > 50% ExecTime → IO 瓶颈 |
| `SpillDataSize` | Profile | 落盘数据量 | > 0 → 内存压力 |
| `JoinProbeTime` | Profile join operator | Hash join probe 耗时 | > 30% ExecTime → join 瓶颈 |
| `FragmentInstanceNum` | Profile / be/log | fragment instance 数 | > 1000 → 并发过高 |

```sql
SET enable_profile = true;
-- 执行查询后在 FE HTTP 获取 Profile:
curl -s "http://$FE:8030/api/query_profile?query_id=$QID"
```

## Compaction 指标

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `tablet_base_max_compaction_score` | BE /metrics | 最大 base score | > 100 |
| `tablet_cumulative_max_compaction_score` | BE /metrics | 最大 cumu score | > 50 |
| `compaction_bytes_total` | BE /metrics | compaction 写入 bytes/s | 接近磁盘带宽 → 磁盘瓶颈 |
| `version_count` | `SHOW TABLET` | tablet 版本数 | > 1800 → 接近 max(2000) |
| `CloneTaskQueue` | `SHOW PROC '/tasks'` | clone 任务积压 | > 50 |

```bash
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep compaction --warn
```

**Base vs Cumulative 区分**：
- `type=1` = BASE_COMPACTION → base score，问题方向是 base rowset 合并
- `type=2` = CUMULATIVE_COMPACTION → cumu score，问题方向是写入频率

## Node 内存指标

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `process_mem_usage` | BE /metrics 或 `/profile` | BE 进程 RSS | > 85% mem_limit |
| `MemTrackerLimiter` | `be.WARNING` | 内存追踪器超限 | 任何出现 → 内存压力 |
| `jemalloc_retained_bytes` | BE /metrics | jemalloc 保留未归还 OS 的内存 | > 5GB → 碎片严重 |
| `DataPageCache[size]` | `/profile` | DataPageCache 大小 | 需结合 RSS 判断 |
| `SegmentCache[size]` | `/profile` | SegmentCache 大小 | 需结合 RSS 判断 |
| `QueryCache@cache` | `/profile` | QueryCache 大小 | > 20% mem_limit → 考虑降低 |
| `file_cache_need_update_lru_blocks_length` | BE bvar | FileCache LRU queue 长度 | > 100000 → 可能堆积 |

```bash
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep "memory|jemalloc|cache" --warn
```

**RSS vs MemTracker 差距**：
- jemalloc arena 碎片：10-20% overhead
- brpc buffer pools：不在 MemTracker 内
- Thread stacks：~8MB × thread count
- 实践：`mem_limit` = 系统 RAM 的 60-70%，留出 overhead 空间

## Import 指标

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `LoadTime` | `SHOW LOAD` | 导入总耗时 | > 10min（大表除外） |
| `publish_timeout` | be/log | 版本发布超时 | 出现 → compaction 或 tablet 数问题 |
| `wal_size` | `wal-du` 命令 | WAL 磁盘用量 | > 磁盘 50% → 消费跟不上 |
| `group_commit_insert_threads` | be.conf | commit worker 池大小 | 忙碌率 > 80% |
| `heavy_work_pool_active` | BE bvar | heavy pool active 线程数 | = max → 可能排队 |

```bash
./scripts/doris-debug wal-du /path/to/be/storage
./scripts/doris-debug log-grep be/log --pack group_commit
```

## Cloud 存算分离指标

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `file_cache_hit_ratio` | BE /metrics | 本地缓存命中率 | < 50% → cache 效果差 |
| `s3_read_bytes_total` | BE /metrics | S3 读字节（缓存未命中时） | 持续高位 → cache miss 或 warmup 不足 |
| `meta_service_rpc_latency` | FE 日志或监控 | meta-service RPC 耗时 | P99 > 100ms |
| `compute_group_fragment_num` | FE cloud cluster check | 计算组 fragment 并发数 | > 2000 → 并发过高 |
| `file_cache_size` | BE /metrics | file cache 当前占用 | 接近 file_cache_path 配置的 total_size → 考虑扩容 |

```bash
./scripts/doris-debug be-metrics --be http://$BE:8040 --grep "file_cache|s3"
```

## Resource Isolation 指标

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `ActiveQueries` | `SHOW WORKLOAD GROUPS` | 当前活跃查询 | = max_concurrency |
| `QueuedQueries` | `SHOW WORKLOAD GROUPS` | 排队查询数 | > 0 持续 → 队列饱和 |
| `QueueTime` | Profile | 查询排队时间 | > 30s |
| `cpu_hard_limit` | cgroup | CPU 硬限制 | 使用率 > 90% |
| `memory_limit_bytes` | cgroup | cgroup 内存限制 | RSS > 85% |

```sql
SHOW WORKLOAD GROUPS\G
SELECT * FROM information_schema.workload_group_resource_usage;
```

```bash
cat /sys/fs/cgroup/cpu/doris/<wg_id>/cpu.shares
cat /sys/fs/cgroup/memory/doris/<wg_id>/memory.limit_in_bytes
```

## FE 自身健康

| 指标 | 来源 | 含义 | 告警阈值 |
|------|------|------|----------|
| `Old Gen usage` | `jmap -heap` | FE JVM Old Gen 使用率 | > 85% → 接近 OOM |
| `GC time` | `fe.gc.log` | GC 耗时 | > 10s / 次的 Full GC |
| `number_of_queries` | `SHOW PROC '/current_queries'` | 当前运行查询数 | > 1000 |
| `BDBJE log file count` | `ls fe/doris-meta/bdb/*.jdb \| wc -l` | BDBJE 日志文件数 | 增长异常 → 可能磁盘问题 |
| `Edit log replay gap` | `SHOW FRONTENDS` → `ReplayedJournalId` | 从 Master 的日志回放延迟 | > 1000 |

```bash
jstack <fe_pid> | grep -A5 "BLOCKED\|WAITING" | head -30
jmap -heap <fe_pid> 2>/dev/null | grep "Old\\|Eden"
```
