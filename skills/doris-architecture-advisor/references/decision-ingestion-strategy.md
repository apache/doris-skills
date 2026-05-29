# Ingestion Strategy

Choose the ingestion path based on throughput, producer shape, and latency requirements.

## Decision Framework

| Condition | Recommendation | Source |
|-----------|---------------|--------|
| Application can batch 10K-100K rows per insert | Stream Load (HTTP) or INSERT INTO VALUES | official |
| Many small inserts from distributed producers that cannot batch | Group Commit (`group_commit = async_mode`) | official |
| Continuous streaming from MySQL/PostgreSQL with CDC | Flink CDC → Stream Load | official |
| Continuous streaming from Kafka topics | Routine Load (built-in Kafka consumer) | official |
| Bulk import from S3/HDFS/object storage | Broker Load or `SELECT ... FROM S3()` table function | official |
| Bursty writes from many IoT gateways | Group Commit for real-time + Broker Load for batch backfill | derived |
| Real-time CDC + business data from OLTP databases | Flink CDC with exactly-once semantics | derived |

Reference: [Stream Load](https://doris.apache.org/docs/data-operate/import/stream-load-manual), [Routine Load](https://doris.apache.org/docs/data-operate/import/routine-load-manual), [Group Commit](https://doris.apache.org/docs/data-operate/import/group-commit-manual)

## Stream Load (HTTP API)
Best for application-controlled batch inserts.
```bash
curl -u user:pass -H "label:load_20250101" \
  -T data.csv \
  http://<fe_host>:8080/api/<db>/<table>/_stream_load
```
- Target batch size: 10K-100K rows or 10-100MB per request
- Supports CSV, JSON, Parquet, ORC formats
- Synchronous — caller knows immediately if load succeeded

## Group Commit
Best for high-frequency small writes that cannot batch client-side.
```sql
-- Server-side batching: Apache Doris accumulates small inserts
-- and flushes them together
SET group_commit = async_mode;
INSERT INTO table VALUES (...);
```
- Apache Doris buffers small inserts server-side, flushes as one batch
- Reduces part creation pressure from many small writers
- IoT gateway pattern: each gateway sends small batches → Group Commit merges

## Flink CDC
Best for continuous MySQL/PostgreSQL replication.
- Full snapshot + incremental binlog/WAL streaming
- Exactly-once delivery with Flink checkpointing
- Pair with UNIQUE MoW + `sequence_col` for correct ordering

## Routine Load
Best for continuous Kafka consumption.
- Built-in Kafka consumer, no external framework needed
- Supports JSON, CSV formats from Kafka topics
- Auto-manages offsets and parallelism

## Broker Load
Best for bulk import from object storage.
- Asynchronous — submit job and poll for completion
- Supports S3, GCS, HDFS, OSS
- Use for initial data migration or periodic batch loads

## Write Throughput Reference

Apache Doris achieves tens of GB/s write throughput with:
- Time-series compaction (`compaction_policy = "time_series"`) — millisecond-level compaction, near-zero memory overhead
- Columnar storage with optimized flush
- Vectorized index construction

Benchmark: 13 nodes (16c, 64GB) sustain 1 GB/s continuous write at <20% CPU.
