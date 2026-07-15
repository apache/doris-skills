# Doris 关键配置速查（Per-Domain Config Quick Reference）

> 按诊断域分类的关键配置参数，含默认值、作用和调参方向。

## Query 执行

### 超时控制

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `query_timeout` | 300(s) | 查询超时 | 慢 ETL 查询增大，交互式减小 |
| `nereids_timeout_second` | 30(s) | Nereids 优化器超时 | Plan Time 过长时增大到 60-120 |
| `insert_timeout` | 14400(s) | INSERT 超时 | 大表导入增大 |

### 并发控制

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `parallel_exchange_instance_num` | 100 | exchange instance 数 | E11 时**减小**到 50/32 |
| `parallel_fragment_exec_instance_num` | 8 | fragment instance 数 | E11 时减小到 4 或 1 |
| `parallel_pipeline_task_num` | 0 | pipeline task 数（0=auto） | E11 或 CPU 高时设为 1 |
| `max_instance_num` | 64 | 单 fragment 最大 instance | 减少 fanout |
| `enable_plan_cache` | true | 查询计划缓存 | Plan 竞态时临时关闭验证 |

### Session Variable（排查用）

```sql
SET enable_profile = true;                    -- 启用 Profile
SET disable_join_reorder = true;              -- 跳过 join reorder
SET enable_materialized_view_rewrite = false; -- 跳过 MV rewrite
SET enable_spill = true;                      -- 启用磁盘溢出
SET materialized_view_rewrite_enable_contain_external_table = true;
```

## Compaction

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `max_tablet_version_num` | 2000 | tablet 版本数硬上限 | -235 时临时增大到 5000，但必须同时修复 compaction |
| `time_series_max_tablet_version_num` | 20000 | 时序表版本上限 | 时序场景单独调大 |
| `max_cumulative_compaction_threads` | -1（auto） | cumu compaction 线程数 | cumu score 高时显式设置 |
| `compaction_task_num_per_disk` | 4 | 每盘并发 compaction 数 | 磁盘 IO 未饱和时增大 |
| `compaction_tablet_size_threshold` | 100GB | 超过此大小跳过 base compaction | 大 tablet 场景调大 |
| `base_compaction_interval_seconds_since_last_operation` | 86400 | base compaction 最低间隔 | SC 后调小加速合并 |
| `disable_auto_compaction` | false | 全局禁用 compaction | 紧急止血（如倒排索引重建） |

```bash
# 运行时查看
curl -s "http://$BE:8040/api/show_config" | grep compaction
```

## Node 内存

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `mem_limit` | 80% | BE 内存软限制 | 实际 RSS = mem_limit + 10-20%，容器环境建议 60-70% |
| `max_segment_cache_size` | 0（无限制） | Segment Cache 大小 | 显式设置避免缓存吃满 RSS |
| `storage_page_cache_limit` | 0（无限制） | Page Cache 大小 | 显式限制 |
| `enable_je_purge` | false | jemalloc dirty page 回收 | 内存碎片严重时开启 |
| `chunk_reserved_bytes_limit` | 2GB | chunk 分配器保留内存 | OOM 时减小 |
| `memory_gc_enable` | true | 内存压力时 GC | 保持开启 |
| `process_memory_recovery_enable` | false | OOM 前尝试 cancel query | 建议开启 |

## Import

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `group_commit_insert_threads` | 10 | commit worker 线程 | 消费跟不上时增大 |
| `group_commit_relay_wal_threads` | 10 | WAL relay 线程 | WAL 堆积时增大 |
| `group_commit_data_bytes` | 64MB（table level） | size flush 阈值 | 高频导入调大增吞吐 |
| `group_commit_interval_ms` | 10000（table level） | time flush 阈值 | 高频导入调大减少版本数 |
| `group_commit_wal_max_disk_limit` | 10% | WAL 磁盘上限 | 磁盘大时增大 |
| `tablet_writer_open_rpc_timeout_sec` | 60 | open tablet writer RPC 超时 | Heavy pool 排队严重时增大 |
| `brpc_heavy_work_pool_threads` | 256 | heavy pool 线程数 | 高并发导入时增大（如 384），但需保留 pstack 确认卡点 |
| `enable_redirect_strict_check` | true | Stream Load redirect IP 校验 | 客户端外网时设为 false |

## Cloud 存算分离

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `file_cache_path` | 无 | file cache 路径和容量 | 按 NVMe 容量设置 |
| `file_cache_type` | `whole_file_cache` | 缓存粒度（整文件/子文件） | `sub_file_cache` 减少 S3 list |
| `file_cache_query_limit` | 0 | 单查询 file cache 上限 | 防止单查询吃满 cache |
| `file_cache_background_lru_log_replay_interval_ms` | 1（4.1.8+） | LRU recorder replay 间隔 | 内存泄漏时调小（1000→1） |
| `file_cache_background_lru_log_queue_max_size` | 500000（4.1.8+） | LRU recorder queue 硬上限 | 防止 queue 无限堆积 |
| `s3_max_connections` | 256 | S3 并发连接数 | 高并发时增大 |
| `s3_request_timeout_ms` | 30000 | S3 请求超时 | S3 慢时增大 |

## Resource Isolation

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `enable_workload_group` | true | 启用 Workload Group | cgroup 未配置时 WG 只是建议 |
| `max_concurrency` | (per WG) | WG 最大并发 | 队列堆积时增大 |
| `max_queue_size` | (per WG) | WG 最大排队数 | 排队爆满时增大 |
| `queue_timeout` | (per WG) | 排队超时 | 长时间排队时增大 |
| `cpu_share` | (per WG) | CPU share 权重 | 饥饿 WG 增大 |
| `cpu_hard_limit` | (per WG) | CPU 硬限制 | 单 WG 吃满 CPU 时设置 |

```sql
ALTER WORKLOAD GROUP wg SET ("max_concurrency" = "8", "queue_timeout" = "300");
```

## FE 高可用

| 参数 | 默认值 | 作用 | 调参方向 |
|------|--------|------|----------|
| `-Xmx` / `-Xms` | 取决于部署 | FE JVM heap | OOM 或 GC 频繁时增大 |
| `hive_metastore_client_timeout_second` | 10 | HMS 客户端超时 | HMS 慢时增大 |
| `iceberg_manifest_cache_refresh_interval_s` | 3600 | Iceberg manifest 缓存刷新间隔 | Plan Time 长时增大 |
| `bdbje_cleaner_threads` | 1 | BDBJE 日志清理线程 | .jdb 文件堆积时增大 |
| `meta_dir` | `fe/doris-meta` | FE 元数据目录 | 放到高性能磁盘，预留 20%+ 空间 |
| `priority_networks` | 空 | brpc 绑定网段 | 多网卡环境必须设置 |
