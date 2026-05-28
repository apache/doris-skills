---
title: "Use Case: Time-Series Logs & Events"
impact: CRITICAL
tags: [usecase, logs, events, clickstream, time-series, duplicate]
---
## Use Case: Time-Series Logs & Events
For immutable, append-only data: application logs, click events, IoT sensor readings, audit trails.
### Template
```sql
CREATE TABLE app_events (
    event_time DATETIME NOT NULL,
    app_id INT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    user_id BIGINT,
    payload STRING
) ENGINE=OLAP
DUPLICATE KEY(event_time, app_id, event_type)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(app_id) BUCKETS 10  -- high-volume logs: calculate: data_per_partition_GB × compression / 2
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd"
);
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | DUPLICATE | Logs are immutable — no updates/deletes needed. Fastest scan speed. |
| **Partition** | Dynamic RANGE by DAY | Auto-creates daily partitions, auto-drops old ones (TTL via `start`). |
| **Bucket** | HASH on `app_id` | High cardinality, commonly filtered in WHERE. |
| **Sort Key** | `(event_time, app_id, event_type)` | Time-first enables range scans; app_id enables prefix pruning. |
| **Compression** | ZSTD | Log data has high redundancy — ZSTD compresses 2-3x better than LZ4. |
### Customization Points
- **Retention:** Change `dynamic_partition.start` (e.g., `"-30"` for 30 days)
- **Partition granularity:** `"HOUR"` for very high volume or `"MONTH"` for low volume
- **Bucket key:** If you mostly filter by `user_id`, use `HASH(user_id)` instead
- **Add text search:** Add `INDEX idx_payload(payload) USING INVERTED` for log message search
