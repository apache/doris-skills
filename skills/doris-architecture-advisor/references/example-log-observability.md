# Example: Log & Observability Platform

## Scenario

- **Workload:** Centralized observability — logs + traces + metrics from 200 microservices
- **Ingest rate:** 500 GB/day logs, 50 GB/day traces, 10 GB/day metrics
- **Query patterns:** keyword search on log body, trace ID lookup, service error rate dashboards
- **Latency target:** log search 1-3s, trace lookup <1s, dashboard <1s
- **Retention:** logs 7 days, traces 7 days, metrics 30 days

## Workload Classification

| Sub-workload | Type | Table |
|-------------|------|-------|
| Application logs | Log/Search | `otel_logs` |
| Distributed traces | Log/Search (trace correlation) | `otel_traces` |
| Service metrics | Report / Pre-aggregation | `otel_metrics` |

## Sizing Recommendation

- **Write:** ~560 GB/day ≈ 6.5 MB/s sustained, bursts to 50+ MB/s
- **Hot data:** 7 days × 560GB × 0.1 (ZSTD) = ~390 GB (logs+traces) + 30 days × 10GB × 0.15 = ~45 GB (metrics)
- **Total hot:** ~435 GB → fits 16 vCPU total cluster, 1 TB total cache (Log Storage & Search matrix)
- **QPS:** ~100 (dashboard + search)

## Table Designs

### 1. otel_logs (DUPLICATE — full-text searchable logs)

```sql
CREATE TABLE otel_logs (
    log_time DATETIME NOT NULL,
    service_name VARCHAR(100) NOT NULL,
    severity VARCHAR(10) NOT NULL,
    trace_id VARCHAR(32),
    span_id VARCHAR(16),
    body TEXT,
    resource_attrs VARIANT,
    INDEX idx_body(body) USING INVERTED PROPERTIES("parser" = "unicode"),
    INDEX idx_trace(trace_id) USING INVERTED
) ENGINE=OLAP
DUPLICATE KEY(log_time, service_name, severity)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 12  -- 500 GB/day × 0.05 ZSTD = 25 GB/partition ÷ 2 GB target ≈ 12 buckets
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",
    "compaction_policy" = "time_series",
    "replication_num" = "1"
);
```

### 2. otel_traces (DUPLICATE — trace correlation)

```sql
CREATE TABLE otel_traces (
    start_time DATETIME NOT NULL,
    service_name VARCHAR(100) NOT NULL,
    trace_id VARCHAR(32) NOT NULL,
    span_id VARCHAR(16) NOT NULL,
    parent_span_id VARCHAR(16),
    operation_name VARCHAR(200),
    duration_ms BIGINT,
    status_code TINYINT,
    INDEX idx_trace(trace_id) USING INVERTED
) ENGINE=OLAP
DUPLICATE KEY(start_time, service_name, trace_id)
PARTITION BY RANGE(start_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 3  -- 50 GB/day × 0.1 ZSTD = 5 GB/partition ÷ 2 GB target ≈ 3 buckets
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",
    "replication_num" = "1"
);
```

### 3. otel_metrics (AGGREGATE — pre-aggregated service metrics)

```sql
CREATE TABLE otel_metrics (
    metric_time DATETIME NOT NULL,
    service_name VARCHAR(100) NOT NULL,
    metric_name VARCHAR(200) NOT NULL,
    value_sum DOUBLE SUM DEFAULT "0",
    value_count BIGINT SUM DEFAULT "0"
) ENGINE=OLAP
AGGREGATE KEY(metric_time, service_name, metric_name)
PARTITION BY RANGE(metric_time) ()
DISTRIBUTED BY HASH(service_name) BUCKETS 3  -- 10 GB/day aggregated metrics, small per-partition → 3 buckets
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
```

## Key Decisions

| Decision | Why | Source |
|----------|-----|--------|
| Shared bucket key `service_name` | Potential colocation JOINs across all 3 tables | derived |
| Inverted index on `body` with unicode parser | Full-text log search via MATCH_ANY/MATCH_ALL | official |
| Inverted index on `trace_id` | Fast trace lookup without sort key position | official |
| ZSTD compression on logs/traces | Log data 10-20x compression ratio | official |
| 7-day TTL logs, 30-day metrics | Logs are high-volume short-lived; metrics are compact long-lived | field |
| AGGREGATE for metrics | Auto-aggregates on ingest; dashboard queries hit pre-computed values | official |
| VARIANT for resource_attrs | OpenTelemetry resource attributes vary by service | derived |
