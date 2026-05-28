---
title: "Use Case: Observability Platform"
impact: CRITICAL
tags: [usecase, observability, logs, traces, metrics, opentelemetry, grafana]
---
## Use Case: Observability Platform
For building a full observability stack: logs + metrics + traces.
### Table 1: Logs (DUPLICATE)
```sql
CREATE TABLE otel_logs (
    log_time DATETIME NOT NULL, service_name VARCHAR(100) NOT NULL,
    severity VARCHAR(10) NOT NULL, trace_id VARCHAR(32), span_id VARCHAR(16),
    body TEXT, resource_attributes STRING,
    INDEX idx_body(body) USING INVERTED PROPERTIES("parser" = "unicode")
) ENGINE=OLAP DUPLICATE KEY(log_time, service_name, severity)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 10  -- high-volume logs: ~100 GB/day × 0.05 ZSTD / 2 GB ≈ 2.5, rounded up for growth
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="DAY",
    "dynamic_partition.start"="-7","dynamic_partition.end"="3",
    "dynamic_partition.prefix"="p","compression"="zstd",
    "bloom_filter_columns"="trace_id");
```
### Table 2: Traces (DUPLICATE)
```sql
CREATE TABLE otel_traces (
    start_time DATETIME NOT NULL, service_name VARCHAR(100) NOT NULL,
    trace_id VARCHAR(32) NOT NULL, span_id VARCHAR(16) NOT NULL,
    parent_span_id VARCHAR(16), operation_name VARCHAR(200),
    duration_ms BIGINT, status_code TINYINT
) ENGINE=OLAP DUPLICATE KEY(start_time, service_name, trace_id)
PARTITION BY RANGE(start_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 3  -- traces: lower volume than logs, ~small per partition
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="DAY",
    "dynamic_partition.start"="-7","dynamic_partition.end"="3",
    "dynamic_partition.prefix"="p","compression"="zstd",
    "bloom_filter_columns"="trace_id");
```
### Table 3: Metrics (AGGREGATE)
```sql
CREATE TABLE otel_metrics (
    metric_time DATETIME NOT NULL, service_name VARCHAR(100) NOT NULL,
    metric_name VARCHAR(200) NOT NULL,
    value DOUBLE SUM DEFAULT "0", count BIGINT SUM DEFAULT "0"
) ENGINE=OLAP AGGREGATE KEY(metric_time, service_name, metric_name)
PARTITION BY RANGE(metric_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 3  -- pre-aggregated metrics: small per partition
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="DAY",
    "dynamic_partition.start"="-30","dynamic_partition.end"="3","dynamic_partition.prefix"="p");
```
### Design Principles
- **Shared bucket key:** All tables use `HASH(service_name)` for potential colocation JOINs
- **Short retention for logs/traces:** 7-day TTL; **Longer for metrics:** 30-day TTL
- **Text search on logs:** Inverted index on `body` with unicode parser
- **Trace correlation:** BloomFilter on `trace_id` for fast trace lookup
