# Deployment Mode Selection

Choose between integrated (storage-compute coupled) and decoupled (storage-compute separated) before sizing.

## Decision Framework

| Condition | Recommendation | Source |
|-----------|---------------|--------|
| Public cloud with S3/GCS/OSS available | Decoupled (Cloud mode) | derived |
| Private DC with reliable HDFS/Ceph/MinIO | Decoupled (self-hosted) | derived |
| Private DC without shared storage | Integrated | official |
| Write-heavy workload (ingest throughput is primary concern) | Decoupled — 2x write speedup (single replica vs 3-replica) | field |
| Latency-critical point queries (<30ms SLA) | Integrated — local SSD avoids object storage latency | field |
| Multi-tenant with workload isolation needed | Decoupled — independent compute groups share data | official |
| Quick POC or dev/test environment | Integrated — simpler, no external dependencies | derived |
| Need elastic scale-up/down by time of day | Decoupled — add/remove BEs without data migration | official |

## Performance Characteristics

### Write performance
Decoupled is ~2x faster than integrated. Integrated writes 3 replicas with in-memory sort + compaction on each. Decoupled writes 1 replica to object storage.

### Query performance
- **Fully cached:** Same as integrated.
- **Fully remote (cache miss):** 30%+ slower — depends on query and network bandwidth.
- **Rule of thumb:** 60% of data cached locally → 95% cache hit rate → production-ready.

### Cache strategy
- Maintain cache hit rate ≥ 90% in production.
- Set table-level cache TTL for hot/cold separation:

```sql
-- Dimension tables: cache forever
ALTER TABLE dim_stores SET ("file_cache_ttl_seconds" = "0");

-- Fact tables: cache last 7 days
ALTER TABLE fact_orders SET ("file_cache_ttl_seconds" = "604800");
```

## Cloud Mode Forced Properties

All Cloud-mode tables must set:
```sql
PROPERTIES ("replication_num" = "1");
```

Additional cloud constraints:
- UNIQUE MoW tables must use HASH bucketing (not RANDOM)
- Delete bitmap syncs via RPC in cloud mode (slight write overhead)
- File cache controls query performance — monitor cache hit rate

## Object Storage Requirements (self-hosted decoupled)
- Single-bucket access latency: milliseconds
- Single-bucket capacity: PB-scale
- Network bandwidth (up + down): ≥ 15 Gbps each
