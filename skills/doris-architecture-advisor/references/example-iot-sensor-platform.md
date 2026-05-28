# Example: IoT Sensor Platform

## Scenario

- **Workload:** IoT device monitoring and analytics
- **Devices:** 50,000+ sensors across multiple protocols (MQTT, Modbus, OPC-UA)
- **Ingest rate:** 10K readings/sec (50K devices × 1 reading/5s), ~40 MB/s JSON after parsing
- **Data volume:** 210 GB/day raw, 75 TB/year
- **Query patterns:** real-time device status, historical trend analysis, alert threshold monitoring, device log search
- **Latency target:** dashboard queries 1-3s, point queries <100ms
- **Retention:** 90 days hot, 1 year cold archive to object storage
- **Special:** devices go offline/online, metadata updates, out-of-order data from network delays

## Workload Classification

**Composite workload** decomposed into:

| Sub-workload | Type | Table |
|-------------|------|-------|
| Sensor time-series readings | Log/Time-series | `sensor_readings` |
| Device state tracking (digital twin) | Mutable state / Point query | `device_shadow` |
| Device logs (fault diagnosis) | Log/Search | `device_logs` |
| Device statistics (connection counts, uptime) | Report / Pre-aggregation | `device_stats` |

## Sizing Recommendation

- **Write:** 40 MB/s sustained → fits 32 vCPU total cluster (1 TB total cache)
- **Hot data:** 90 days × 210GB/day × 0.1 (ZSTD compression) = ~1.9 TB
- **QPS:** Mixed — dashboard ~100 QPS + point query ~5K QPS
- **Recommendation:** 32 vCPU total, 1 TB total cache for analytics. Consider separate compute group for point query if >10K QPS

**Storage estimate:**
```
75 TB/year raw × ZSTD 10x compression × 1 replica = 7.5 TB/year stored
3-year retention: ~22.5 TB
```

**FE:** 3 nodes for HA (managed in Cloud mode).

## Architecture

```
Sensors → IoT Gateway → Kafka
                          ├─→ Stream Load → {{PRODUCT_NAME}} (sensor_readings, device_shadow)
                          └─→ Cold archive → Object Storage (Minio/S3)

MySQL (ERP/CRM) → Flink CDC → {{PRODUCT_NAME}} (business data)

{{PRODUCT_NAME}} → Grafana (dashboards)
       → API Server (device status point queries)
       → Flink (real-time alerts)
```

## Table Designs

### 1. sensor_readings (DUPLICATE — append-only time-series)

```sql
CREATE TABLE sensor_readings (
    device_id VARCHAR(64) NOT NULL,         -- Per decision-time-series: entity as sort key first
    reading_time DATETIME(3) NOT NULL,      -- Millisecond precision for IoT
    sensor_type VARCHAR(30) NOT NULL,       -- temperature, humidity, voltage, etc.
    value DOUBLE,
    quality_flag TINYINT DEFAULT 0,         -- 0=good, 1=suspect, 2=bad
    data VARIANT                            -- Per decision-data-model: VARIANT for multi-protocol payloads
) ENGINE=OLAP
DUPLICATE KEY(device_id, reading_time, sensor_type)
PARTITION BY RANGE(reading_time) ()
DISTRIBUTED BY HASH(device_id) BUCKETS 10    -- 210 GB/day × 0.1 ZSTD = 21 GB/partition ÷ 2 GB target = ~10
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-90",      -- 90-day retention
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",                 -- Per decision-time-series: ZSTD for IoT numeric data
    "compaction_policy" = "time_series",    -- Per decision-time-series: optimized compaction
    "replication_num" = "1"                 -- Cloud mode
);
```

### 2. device_shadow (UNIQUE MoW — mutable device state)

```sql
CREATE TABLE device_shadow (
    device_id VARCHAR(64) NOT NULL,
    last_seen DATETIME(3) NOT NULL,
    status VARCHAR(20) DEFAULT 'unknown',   -- online, offline, maintenance
    firmware_version VARCHAR(30),
    location VARCHAR(100),
    owner VARCHAR(100),
    config VARIANT                          -- Device-specific config as semi-structured
) ENGINE=OLAP
UNIQUE KEY(device_id)
DISTRIBUTED BY HASH(device_id) BUCKETS 3
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "last_seen",  -- Per decision-mutable-state: handles out-of-order
    "store_row_column" = "true",                    -- Per decision-mutable-state: enables point query
    "light_schema_change" = "true",
    "replication_num" = "1"
);
```

### 3. device_logs (DUPLICATE — log search with inverted index)

```sql
CREATE TABLE device_logs (
    device_id VARCHAR(64) NOT NULL,
    log_time DATETIME NOT NULL,
    log_level VARCHAR(10) NOT NULL,         -- INFO, WARN, ERROR, FATAL
    message TEXT,
    INDEX idx_msg(message) USING INVERTED PROPERTIES("parser" = "unicode"),
    INDEX idx_level(log_level) USING INVERTED
) ENGINE=OLAP
DUPLICATE KEY(device_id, log_time, log_level)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(device_id) BUCKETS 3
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",      -- 30-day log retention
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",
    "compaction_policy" = "time_series",
    "replication_num" = "1"
);
```

### 4. device_stats (AGGREGATE — pre-computed device metrics)

```sql
CREATE TABLE device_stats (
    stat_date DATE NOT NULL,
    device_type VARCHAR(50) NOT NULL,
    region VARCHAR(50) NOT NULL,
    device_count BIGINT SUM DEFAULT "0",
    online_count BIGINT SUM DEFAULT "0",
    total_readings BIGINT SUM DEFAULT "0",
    error_count BIGINT SUM DEFAULT "0",
    unique_devices BITMAP BITMAP_UNION      -- Exact distinct device count
) ENGINE=OLAP
AGGREGATE KEY(stat_date, device_type, region)
PARTITION BY RANGE(stat_date) ()
DISTRIBUTED BY HASH(device_type) BUCKETS 3  -- aggregated stats, small per-month partition → 3 buckets
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "1",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
```

## Decision Provenance

| Decision | Source |
|----------|--------|
| DUPLICATE for sensor_readings | official — append-only, fastest scan |
| VARIANT for multi-protocol data | official — 8x faster than JSON, auto schema evolution |
| time_series compaction | derived — IoT write pattern matches (ordered, steady rate) |
| UNIQUE MoW for device_shadow | official — needs upsert for state changes |
| sequence_col on last_seen | official — handles out-of-order IoT events |
| store_row_column for point queries | official — single I/O per device lookup |
| Inverted index on log message | official — enables MATCH_ANY/MATCH_ALL search |
| AGGREGATE + BITMAP_UNION | official — exact count-distinct without raw storage |
| ZSTD compression | derived — IoT data has high redundancy |
| 90-day / 30-day dynamic partition TTL | field — common IoT retention windows |
