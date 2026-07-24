# Doris Key Config Quick Reference (Per-Domain Config Quick Reference)

> Key configuration parameters organized by diagnostic domain, with defaults, purpose, and tuning direction.

## Query Execution

### Timeout Control

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `query_timeout` | 300(s) | Query timeout | Increase for slow ETL queries, decrease for interactive queries |
| `nereids_timeout_second` | 30(s) | Nereids optimizer timeout | Increase to 60-120 when Plan Time is too long |
| `insert_timeout` | 14400(s) | INSERT timeout | Increase for large table loads |

### Concurrency Control

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `parallel_exchange_instance_num` | 100 | Number of exchange instances | **Decrease** to 50/32 on E11 |
| `parallel_fragment_exec_instance_num` | 8 | Number of fragment instances | Decrease to 4 or 1 on E11 |
| `parallel_pipeline_task_num` | 0 | Number of pipeline tasks (0=auto) | Set to 1 on E11 or high CPU |
| `max_instance_num` | 64 | Max instances per fragment | Reduce fanout |
| `enable_plan_cache` | true | Query plan cache | Temporarily disable to verify plan races |

### Session Variables (for Troubleshooting)

```sql
SET enable_profile = true;                    -- Enable Profile
SET disable_join_reorder = true;              -- Skip join reorder
SET enable_materialized_view_rewrite = false; -- Skip MV rewrite
SET enable_spill = true;                      -- Enable disk spill
SET materialized_view_rewrite_enable_contain_external_table = true;
```

## Compaction

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `max_tablet_version_num` | 2000 | Hard limit on tablet version count | On -235, temporarily increase to 5000, but compaction must be fixed at the same time |
| `time_series_max_tablet_version_num` | 20000 | Version limit for time-series tables | Increase separately for time-series scenarios |
| `max_cumulative_compaction_threads` | -1 (auto) | Number of cumu compaction threads | Set explicitly when cumu score is high |
| `compaction_task_num_per_disk` | 4 | Concurrent compactions per disk | Increase when disk IO is not saturated |
| `compaction_tablet_size_threshold` | 100GB | Tablets larger than this skip base compaction | Increase for large tablet scenarios |
| `base_compaction_interval_seconds_since_last_operation` | 86400 | Minimum interval for base compaction | Decrease after SC to speed up merging |
| `disable_auto_compaction` | false | Globally disable compaction | Emergency mitigation (e.g., inverted index rebuild) |

```bash
# View at runtime
curl -s "http://$BE:8040/api/show_config" | grep compaction
```

## Node Memory

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `mem_limit` | 80% | BE memory soft limit | Actual RSS = mem_limit + 10-20%; 60-70% recommended in container environments |
| `max_segment_cache_size` | 0 (unlimited) | Segment Cache size | Set explicitly to prevent the cache from consuming all RSS |
| `storage_page_cache_limit` | 0 (unlimited) | Page Cache size | Limit explicitly |
| `enable_je_purge` | false | jemalloc dirty page reclamation | Enable when memory fragmentation is severe |
| `chunk_reserved_bytes_limit` | 2GB | Memory reserved by the chunk allocator | Decrease on OOM |
| `memory_gc_enable` | true | GC under memory pressure | Keep enabled |
| `process_memory_recovery_enable` | false | Try to cancel queries before OOM | Recommended to enable |

## Import

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `group_commit_insert_threads` | 10 | Commit worker threads | Increase when consumption cannot keep up |
| `group_commit_relay_wal_threads` | 10 | WAL relay threads | Increase when WAL piles up |
| `group_commit_data_bytes` | 64MB (table level) | Size flush threshold | Increase for high-frequency loads to improve throughput |
| `group_commit_interval_ms` | 10000 (table level) | Time flush threshold | Increase for high-frequency loads to reduce version count |
| `group_commit_wal_max_disk_limit` | 10% | WAL disk limit | Increase when the disk is large |
| `tablet_writer_open_rpc_timeout_sec` | 60 | open tablet writer RPC timeout | Increase when heavy pool queuing is severe |
| `brpc_heavy_work_pool_threads` | 256 | Number of heavy pool threads | Increase under high-concurrency loads (e.g., 384), but capture pstack first to confirm the stuck point |
| `enable_redirect_strict_check` | true | Stream Load redirect IP check | Set to false when the client is on an external network |

## Cloud Storage-Compute Separation

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `file_cache_path` | none | File cache path and capacity | Set according to NVMe capacity |
| `file_cache_type` | `whole_file_cache` | Cache granularity (whole file / sub-file) | `sub_file_cache` reduces S3 list calls |
| `file_cache_query_limit` | 0 | Per-query file cache limit | Prevents a single query from consuming the whole cache |
| `file_cache_background_lru_log_replay_interval_ms` | 1 (4.1.8+) | LRU recorder replay interval | Decrease on memory leak (1000→1) |
| `file_cache_background_lru_log_queue_max_size` | 500000 (4.1.8+) | Hard limit of the LRU recorder queue | Prevents unbounded queue growth |
| `s3_max_connections` | 256 | S3 concurrent connections | Increase under high concurrency |
| `s3_request_timeout_ms` | 30000 | S3 request timeout | Increase when S3 is slow |

## Resource Isolation

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `enable_workload_group` | true | Enable Workload Group | Without cgroup configured, WG is only advisory |
| `max_concurrency` | (per WG) | WG max concurrency | Increase when the queue piles up |
| `max_queue_size` | (per WG) | WG max queue size | Increase when the queue overflows |
| `queue_timeout` | (per WG) | Queue timeout | Increase when queuing takes long |
| `cpu_share` | (per WG) | CPU share weight | Increase for starving WGs |
| `cpu_hard_limit` | (per WG) | CPU hard limit | Set when a single WG consumes all CPU |

```sql
ALTER WORKLOAD GROUP wg SET ("max_concurrency" = "8", "queue_timeout" = "300");
```

## FE High Availability

| Parameter | Default | Purpose | Tuning Direction |
|------|--------|------|----------|
| `-Xmx` / `-Xms` | Depends on deployment | FE JVM heap | Increase on OOM or frequent GC |
| `hive_metastore_client_timeout_second` | 10 | HMS client timeout | Increase when HMS is slow |
| `iceberg_manifest_cache_refresh_interval_s` | 3600 | Iceberg manifest cache refresh interval | Increase when Plan Time is long |
| `bdbje_cleaner_threads` | 1 | BDBJE log cleanup threads | Increase when .jdb files pile up |
| `meta_dir` | `fe/doris-meta` | FE metadata directory | Place on a high-performance disk with 20%+ space reserved |
| `priority_networks` | empty | brpc binding subnet | Must be set in multi-NIC environments |
