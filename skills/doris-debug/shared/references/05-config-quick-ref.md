# Doris Key Config Quick Reference (Per-Domain Config Quick Reference)

> Key configuration parameters organized by diagnostic domain, with defaults, purpose, and tuning direction.
>
> **Status column**: every row was checked against `apache/doris` master
> (`6261b18`, 2026-11-25). Values are `current` (matches master), `changed`
> (master default differs from older guidance), `renamed` (the knob exists under a new
> name), `removed` (no definition anywhere on master), `legacy` (the name is still
> accepted but no longer has a field behind it), `table property` (not a BE config) or
> `unverified` (could not be located on master). A deployed 3.x/4.x cluster may still
> accept the old names and defaults: check `be/src/common/config.cpp` on the branch you
> actually run before changing anything.

## Query Execution

### Timeout Control

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `query_timeout` | 300(s) | Query timeout | Increase for slow ETL queries, decrease for interactive queries | unverified: master moved session variables to a generated framework, confirm with `SHOW VARIABLES LIKE 'query_timeout'` |
| `nereids_timeout_second` | 30(s) | Nereids optimizer timeout | Increase to 60-120 when Plan Time is too long | current (`SessionVariable.nereidsTimeoutSecond = 30`) |
| `insert_timeout` | 14400(s) | INSERT timeout | Increase for large table loads | unverified: same framework move as `query_timeout` |

### Concurrency Control

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `parallel_exchange_instance_num` | 100 | Number of exchange instances | Do not tune this on the pipeline engine — use `parallel_pipeline_task_num` | legacy: only a constant remains (`SessionVariable.java`), no field behind it |
| `parallel_fragment_exec_instance_num` | 8 | Number of fragment instances | Do not tune this on the pipeline engine — use `parallel_pipeline_task_num` | legacy: only a user-property mapping remains (`UserProperty.java`) |
| `parallel_pipeline_task_num` | 0 | Number of pipeline tasks (0=auto) | Set to 1 on E11 or high CPU | current (`SessionVariable.parallelPipelineTaskNum = 0`) |
| `max_instance_num` | 64 | Max instances per fragment | Reduce fanout | current (`SessionVariable.maxInstanceNum = 64`) |
| `enable_plan_cache` | true | Query plan cache | Temporarily disable to verify plan races | removed: no definition on master |

### Session Variables (for Troubleshooting)

```sql
SET enable_profile = true;                    -- Enable Profile
SET disable_join_reorder = true;              -- Skip join reorder
SET enable_materialized_view_rewrite = false; -- Skip MV rewrite
SET enable_spill = true;                      -- Enable disk spill
SET materialized_view_rewrite_enable_contain_external_table = true;
```

## Compaction

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `max_tablet_version_num` | 2000 | Hard limit on tablet version count | On -235, temporarily increase to 5000, but compaction must be fixed at the same time | current (`config.cpp:956`) |
| `time_series_max_tablet_version_num` | 20000 | Version limit for time-series tables | Increase separately for time-series scenarios | current (`config.cpp:958`) |
| `max_cumulative_compaction_threads` | -1 (auto) | Number of cumu compaction threads | Set explicitly when cumu score is high | renamed: `max_cumu_compaction_threads` = -1 (`config.cpp:498`) |
| `compaction_task_num_per_disk` | 4 | Concurrent compactions per disk | Increase when disk IO is not saturated | current (`config.cpp:562`) |
| `compaction_tablet_size_threshold` | 100GB | Tablets larger than this skip base compaction | Increase for large tablet scenarios | removed: no definition on master and no replacement knob |
| `base_compaction_interval_seconds_since_last_operation` | 86400 | Minimum interval for base compaction | Decrease after SC to speed up merging | current (`config.cpp:2107`) |
| `disable_auto_compaction` | false | Globally disable compaction | Emergency mitigation (e.g., inverted index rebuild) | current (`config.cpp:469`) |

```bash
# View at runtime
curl -s "http://$BE:8040/api/show_config" | grep compaction
```

## Node Memory

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `mem_limit` | 90% | BE memory soft limit | Actual RSS = mem_limit + 10-20%; 60-70% recommended in container environments | changed: master default is 90% (`config.cpp:139`); the 80% guidance belongs to older releases |
| `max_segment_cache_size` | 0 (unlimited) | Segment Cache size | Set explicitly to prevent the cache from consuming all RSS | removed: use `segment_cache_capacity` (-1, `config.cpp:1565`), `segment_cache_memory_percentage` (5, :1568) or `disable_segment_cache` (false, :420) |
| `storage_page_cache_limit` | 20% | Page Cache size | Limit explicitly | changed: master default is 20% (`config.cpp:430`), not unlimited |
| `enable_je_purge` | false | jemalloc dirty page reclamation | Enable when memory fragmentation is severe | renamed: `enable_je_purge_dirty_pages` = true (`config.cpp:761`) |
| `chunk_reserved_bytes_limit` | 2GB | Memory reserved by the chunk allocator | Decrease on OOM | removed: no definition on master |
| `memory_gc_enable` | true | GC under memory pressure | Keep enabled | removed: the master knob is inverted, `disable_memory_gc` = false (`config.cpp:187`) |
| `process_memory_recovery_enable` | false | Try to cancel queries before OOM | Recommended to enable | removed: no definition on master |

## Import

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `group_commit_insert_threads` | 10 | Commit worker threads | Increase when consumption cannot keep up | current (`config.cpp:1687`) |
| `group_commit_relay_wal_threads` | 10 | WAL relay threads | Increase when WAL piles up | current (`config.cpp:1685`) |
| `group_commit_data_bytes` | 64MB (table level) | Size flush threshold | Increase for high-frequency loads to improve throughput | table property: read per table by `group_commit_mgr`, not a BE config; default unverified |
| `group_commit_interval_ms` | 10000 (table level) | Time flush threshold | Increase for high-frequency loads to reduce version count | table property: not a BE config; default unverified |
| `group_commit_wal_max_disk_limit` | 10% | WAL disk limit | Increase when the disk is large | current (`config.cpp:1694`) |
| `tablet_writer_open_rpc_timeout_sec` | 60 | open tablet writer RPC timeout | Increase when heavy pool queuing is severe | current (`config.cpp:715`) |
| `brpc_heavy_work_pool_threads` | -1 (auto) | Number of heavy pool threads | Increase under high-concurrency loads (e.g., 384), but capture pstack first to confirm the stuck point | changed: master default is -1 (`config.cpp:684`), not 256 |
| `enable_redirect_strict_check` | true | Stream Load redirect IP check | Set to false when the client is on an external network | removed: no definition on master |

## Cloud Storage-Compute Separation

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `file_cache_path` | `[{"path":"${DORIS_HOME}/file_cache"}]` | File cache path and capacity | Set according to NVMe capacity | current (`config.cpp:1279`) |
| `file_cache_type` | `whole_file_cache` | Cache granularity (whole file / sub-file) | `sub_file_cache` reduces S3 list calls | removed: whole-file cache was replaced by the block file cache; tune `file_cache_each_block_size` (`config.cpp:1280`) instead |
| `file_cache_query_limit` | 0 | Per-query file cache limit | Prevents a single query from consuming the whole cache | replaced: boolean `enable_file_cache_query_limit` = false (`config.cpp:1283`) |
| `file_cache_background_lru_log_replay_interval_ms` | 1 (4.1.8+) | LRU recorder replay interval | Decrease on memory leak (1000→1) | current (`config.cpp:1337`) |
| `file_cache_background_lru_log_queue_max_size` | 500000 (4.1.8+) | Hard limit of the LRU recorder queue | Prevents unbounded queue growth | current (`config.cpp:1336`) |
| `s3_max_connections` | 256 | S3 concurrent connections | Increase under high concurrency | removed: use `min_s3_file_system_thread_num` (16, `config.cpp:1140`) and `max_s3_file_system_thread_num` (64, :1141) |
| `s3_request_timeout_ms` | 30000 | S3 request timeout | Increase when S3 is slow | removed: no config definition on master |

## Resource Isolation

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `enable_workload_group` | true | Enable Workload Group | Without cgroup configured, WG is only advisory | current (`Config.enable_workload_group = true`) |
| `max_concurrency` | (per WG) | WG max concurrency | Increase when the queue piles up | workload-group attribute, not a BE config |
| `max_queue_size` | (per WG) | WG max queue size | Increase when the queue overflows | workload-group attribute, not a BE config |
| `queue_timeout` | (per WG) | Queue timeout | Increase when queuing takes long | workload-group attribute, not a BE config |
| `cpu_share` | (per WG) | CPU share weight | Increase for starving WGs | workload-group attribute, not a BE config |
| `cpu_hard_limit` | (per WG) | CPU hard limit | Set when a single WG consumes all CPU | workload-group attribute, not a BE config |

```sql
ALTER WORKLOAD GROUP wg SET ("max_concurrency" = "8", "queue_timeout" = "300");
```

## FE High Availability

| Parameter | Default | Purpose | Tuning Direction | Status on master |
|------|--------|------|----------|------|
| `-Xmx` / `-Xms` | Depends on deployment | FE JVM heap | Increase on OOM or frequent GC | unchanged |
| `hive_metastore_client_timeout_second` | 10 | HMS client timeout | Increase when HMS is slow | current (`Config.java:2149`) |
| `iceberg_manifest_cache_refresh_interval_s` | 3600 | Iceberg manifest cache refresh interval | Increase when Plan Time is long | removed: no definition on master |
| `bdbje_cleaner_threads` | 1 | BDBJE log cleanup threads | Increase when .jdb files pile up | removed: master keeps only the bdbje heartbeat/lock/ack timeouts |
| `meta_dir` | `${DORIS_HOME}/doris-meta` | FE metadata directory | Place on a high-performance disk with 20%+ space reserved | current (`Config.java:217`) |
| `priority_networks` | empty | brpc binding subnet | Must be set in multi-NIC environments | current (`Config.java:323`) |
