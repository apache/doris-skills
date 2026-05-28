# Time-Series Design

For append-only, time-ordered data: sensor readings, logs, events, metrics.

## Decision Framework: Partition Strategy

| Condition | Recommendation | Source |
|-----------|---------------|--------|
| Table < 1 GB total | No partition — just bucketing | official |
| 1-100 GB, time-series | Consider RANGE partition if retention or pruning needed | derived |
| > 100 GB, time-series | Always RANGE partition on time column | official |
| Continuous data, predictable daily volume | Dynamic partition (auto-creates future, auto-drops old) | official |
| Sporadic data (not every day has data) | AUTO PARTITION (creates on demand, no empty partitions) | official |
| Need automated TTL / data lifecycle | Dynamic partition with `start` parameter | official |

**Never combine AUTO PARTITION with dynamic_partition on the same table.**

Reference: [Range Partition](https://doris.apache.org/docs/table-design/data-partitioning/range-partitioning), [Auto Partition](https://doris.apache.org/docs/table-design/data-partitioning/auto-partitioning), [Dynamic Partition](https://doris.apache.org/docs/table-design/data-partitioning/dynamic-partitioning)

## Dynamic Partition for TTL

```sql
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",     -- keep 7 days
    "dynamic_partition.end" = "3",        -- pre-create 3 future days
    "dynamic_partition.prefix" = "p"
);
```

**Granularity selection:**
- HOUR: very high volume (>100GB/day) or sub-hour queries
- DAY: standard time-series (1-100GB/day)
- MONTH: low volume (<1GB/day) or long retention (years)

**Multi-tier retention** (for large historical datasets):
- Recent data: daily partitions (last 90 days)
- Historical: monthly or yearly partitions
- Implement with multiple tables or manual partition management

## Time-Series Compaction

For sustained high-throughput writes (tens of GB/s), enable time-series compaction:

```sql
PROPERTIES (
    "compaction_policy" = "time_series"
);
```

**How it works:** Time-series data is inherently ordered and steady-rate. The compaction skips traditional read-sort-merge and instead hard-links Rowset files into new Rowsets. Millisecond-level compaction with near-zero memory overhead.

**When to use:** Append-only time-series with steady write rate and ordered timestamps.

## Bucket Strategy for Time-Series

| Condition | Bucket strategy | Source |
|-----------|----------------|--------|
| Queries always filter on a specific entity (device_id, user_id) | HASH on that entity | official |
| Queries are full-scan time-range (log search, no entity filter) | RANDOM bucketing | official |
| Need colocation JOIN with dimension table | HASH on join key, match bucket count | official |

### CRITICAL: Always Calculate Explicit Bucket Count

Always write a numeric bucket count in production DDL. Calculate from known data volumes; if inputs are incomplete, choose an explicit conservative fallback rather than automatic bucket sizing.

**Formula:**
```
1. partition_data_GB = daily_raw_data_GB / partition_count_per_day
   (usually 1 partition per day, so = daily_raw_data_GB)

2. compressed_GB = partition_data_GB × compression_ratio
   - CSV/text source data: use 0.3-0.5 (default 0.5)
   - MySQL/OLTP source data: use 0.7
   - ZSTD on logs: use 0.05-0.1
   - ZSTD on structured numeric: use 0.1-0.2

3. buckets = compressed_GB / target_tablet_GB
   - Target: 1-10 GB per tablet (use 2 GB as default target)
   - Max 64 buckets per partition
   - Minimum 1 bucket

4. Round to nearest power of 2 or reasonable number
```

**Worked examples:**

```
Example 1: IoT sensor readings — 210 GB/day raw, ZSTD, daily partitions
  compressed = 210 × 0.1 = 21 GB/partition
  buckets = 21 / 2 = ~10 buckets
  → DISTRIBUTED BY HASH(device_id) BUCKETS 10

Example 2: Application logs — 500 GB/day raw, ZSTD, daily partitions
  compressed = 500 × 0.05 = 25 GB/partition
  buckets = 25 / 2 = ~12 buckets
  → DISTRIBUTED BY HASH(service_name) BUCKETS 12

Example 3: CDC orders — 50 GB total, no partition, LZ4
  compressed = 50 × 0.2 = 10 GB total
  buckets = 10 / 2 = 5 buckets
  → DISTRIBUTED BY HASH(order_id) BUCKETS 5

Example 4: Small dimension table — 500 MB
  → DISTRIBUTED BY RANDOM BUCKETS 3

Example 5: Large fact table — 2 TB/day, ZSTD, daily partitions
  compressed = 2000 × 0.1 = 200 GB/partition
  buckets = 200 / 4 = 50 buckets (target 4 GB for large tablets)
  → DISTRIBUTED BY HASH(user_id) BUCKETS 50
```

**Warning signs after table creation:**
- `SHOW TABLETS FROM table_name` → check size distribution
- Tablets < 100 MB → too many buckets, reduce
- Tablets > 20 GB → too few buckets, increase

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)

## Sort Key for Time-Series

Place columns in this order in DUPLICATE KEY:
1. Most frequently filtered column (often entity_id for pruning)
2. Time column (for range scans)
3. Additional filter columns

```sql
-- Entity-first: queries usually filter by device
DUPLICATE KEY(device_id, event_time, event_type)

-- Time-first: queries usually scan time ranges across all devices
DUPLICATE KEY(event_time, service_name, severity)
```

## Compression

| Data type | Recommendation | Source |
|-----------|---------------|--------|
| Logs, text-heavy data | ZSTD (2-3x better ratio than LZ4) | official |
| Hot analytical data, low-latency reads | LZ4 (faster decompression) | official |
| IoT sensor numeric data | ZSTD (high redundancy in repeating values) | derived |

```sql
PROPERTIES ("compression" = "zstd");
```

ZSTD compresses log data to ~1/10 of raw size. LZ4 to ~1/5.
