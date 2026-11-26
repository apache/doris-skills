---
name: doris-debug-cloud
description: >
  Use for Doris storage-compute separation (cloud mode) issues: meta-service
  latency, cache miss storms, object store throughput, and shared-nothing config
  conflicts in compute groups.
version: 0.2.0
category: cloud
---

# Cloud (Storage-Compute Separation)

## Before proceeding

Confirm cloud mode. Shared-nothing cluster commands (disk rebalance, clone, local tablet repair)
are meaningless in cloud mode. Check:

```sql
SHOW FRONTENDS\G  -- IsCloudMode field (Doris 3.0+)
```

Or inspect `fe.conf` for `cloud_unique_id` or `meta_service_endpoint`.

## Causes

| ID | Cause | Evidence | Source anchor |
|----|-------|----------|---------------|
| A | Meta-service latency | High P99 on `SHOW PROC` / DDL; meta-service RPC spikes | `MetaServiceClient.java` |
| B | Cache miss storm | `local_cache_hit_ratio` near 0; high S3 GET rate post-ingest | `block_file_cache.cpp` |
| C | Object store throughput saturation | S3 throttle errors (503 SlowDown); `Throughput limit exceeded` | `obj_storage_file_system.cpp` |
| D | Compute group imbalance | One compute group idle, another overloaded | `ComputeGroupMgr.java` |
| E | Wrong config for cloud mode | BE OOM from shared-nothing compaction knobs applied in cloud | cloud vs local config divergence |

## 10 min triage

```sql
-- Compute group status
SHOW COMPUTE GROUPS\G

-- File cache hit ratio (Doris 3.0+)
SELECT * FROM information_schema.file_cache_stats;
```

```bash
# BE cache metrics
curl -s "http://$BE:8040/metrics" | grep -E "file_cache|local_cache"

# Object store errors in BE log
grep -rh "$QID" be/log/be.INFO*
grep -r "SlowDown\|503\|Throughput.*exceed" be/log/
```

## Cause A — Meta-service latency

In cloud mode, `SHOW PROC` and DDL go through the meta-service layer, not direct BDBJE. Latency spikes often come from:

1. Meta-service RPC overload — check `meta_service_rpc_timeout_ms` in fe.conf
2. `SHOW PROC '/cluster_health'` on a large cluster — walks every tablet via meta-service

```bash
# Check meta-service health
curl -s "http://$MS_HOST:$MS_PORT/api/health"
```

## Cause B — Cache miss storm

After bulk ingest (INSERT INTO SELECT or Stream Load), the file cache on compute BEs is cold. First query after ingest hits S3 directly — expect 3-10× latency.

```sql
-- Pre-warm cache after bulk ingest
SELECT COUNT(*) FROM new_table;  -- full scan populates file cache
```

Tune cache capacity:
```properties
# be.conf — file cache in cloud mode
file_cache_path = [{"path":"/nvme0/file_cache","total_size":536870912000,"query_limit":107374182400}]
file_cache_each_block_size = 1048576   # block file cache (whole_file_cache no longer exists on master)
```

## Cause C — Object store throttling

S3 has per-prefix request rate limits (~3500 PUT/GET per second per prefix). For high-concurrency cloud workloads:

```properties
# be.conf
# S3 connection settings are storage-vault properties, not BE configs. Defaults:
#   s3.connection.maximum = 50
#   s3.connection.request.timeout = 3000 (ms)
#   s3.connection.timeout = 1000 (ms)
```

For cold tables with large Parquet files, the block file cache already reads at block granularity (`file_cache_each_block_size`, 1 MB default); cap a single query's share with `enable_file_cache_query_limit` or the `query_limit` key of `file_cache_path`.

## Key differences from shared-nothing

| Shared-nothing config | Cloud mode equivalent | Notes |
|----------------------|----------------------|-------|
| `storage_root_path` | `file_cache_path` | Local disk is cache only |
| `SHOW PROC '/backends'` disk | File cache usage | Data durability is in object store |
| Clone / balance | N/A | No tablet migration |
| `max_tablet_version_num` | Still relevant | Compaction runs on compute nodes |
| `compaction_*` knobs | Still relevant | Tune per compute group capacity |

## Source

- `fe/fe-core/src/main/java/org/apache/doris/resource/computegroup/ComputeGroupMgr.java`
- `fe/fe-core/src/main/java/org/apache/doris/cloud/rpc/MetaServiceClient.java`
- `be/src/io/fs/obj_storage_file_system.cpp` (clients: `be/src/io/object_storage/`)
- `be/src/io/cache/block_file_cache.cpp`
