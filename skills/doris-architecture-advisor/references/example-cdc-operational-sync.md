# Example: CDC Operational Sync

## Scenario

- **Workload:** Replicate MySQL order management system for real-time analytics
- **Source:** MySQL orders table (~100M rows, 50GB), ~5000 updates/sec peak
- **Query patterns:** order status reports, revenue by region, fulfillment metrics
- **Latency target:** data freshness <10s, query latency <1s
- **Retention:** full history (no TTL)

## Workload Classification

| Sub-workload | Type | Table |
|-------------|------|-------|
| Order data sync | CDC / Mutable state | `orders_sync` |
| Revenue dashboards | Report analytics | Async MV or query on orders_sync |
| Store dimension | Small lookup table | `dim_stores` |

## Sizing Recommendation

- **Write:** 5K updates/sec × ~500 bytes = ~2.5 MB/s (modest)
- **Hot data:** 50GB × 0.2 (compression) = ~10 GB
- **QPS:** ~200 (dashboard + reports)
- **Recommendation:** 16 vCPU total cluster, 200 GB total cache is sufficient (Report Analytics matrix)

## Table Designs

### 1. orders_sync (UNIQUE MoW — CDC target)

```sql
CREATE TABLE orders_sync (
    order_id BIGINT NOT NULL,
    customer_id INT NOT NULL,
    store_id INT NOT NULL,
    order_date DATETIME NOT NULL,
    update_time DATETIME NOT NULL,
    status VARCHAR(20),
    region VARCHAR(50),
    amount DECIMAL(12,2),
    quantity INT
) ENGINE=OLAP
UNIQUE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 5  -- 50 GB × 0.2 compression = 10 GB ÷ 2 GB target = 5 buckets
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "light_schema_change" = "true",
    "replication_num" = "1"
);
-- No partition: 50GB is below the 100GB threshold.
-- HASH on order_id: point lookups on PK prune to one tablet.
-- sequence_col: Flink CDC events may arrive out of order.
```

### 2. dim_stores (DUPLICATE — small dimension table)

```sql
CREATE TABLE dim_stores (
    store_id INT NOT NULL,
    region VARCHAR(50),
    city VARCHAR(50),
    manager VARCHAR(100)
) ENGINE=OLAP
DUPLICATE KEY(store_id)
DISTRIBUTED BY RANDOM BUCKETS 3
PROPERTIES (
    "replication_num" = "1"
);
-- Small dimension (<1GB): RANDOM bucketing, 3 buckets for even distribution.
-- DUPLICATE not UNIQUE: dimension data rarely changes.
-- For colocation JOIN, switch to HASH(store_id) and match orders_sync bucket count.
```

## Ingestion Architecture

```
MySQL (orders) → Flink CDC → Stream Load → orders_sync (UNIQUE MoW)
                                          → dim_stores (one-time bulk load)
```

**Flink CDC setup:**
- Full snapshot on first run, then incremental binlog streaming
- Exactly-once delivery via Flink checkpointing
- `sequence_col = "update_time"` ensures correct ordering even on replay

## Key Decisions

| Decision | Why | Source |
|----------|-----|--------|
| UNIQUE MoW (not AGG) | CDC requires UPDATE/DELETE support | official |
| No partition | 50GB total — below 100GB partition threshold | official |
| sequence_col on update_time | CDC events may arrive out of order | official |
| Flink CDC (not Routine Load) | MySQL binlog requires CDC framework, not Kafka consumer | derived |
| RANDOM bucket for dim_stores | Small table, no dominant filter column | official |
| No async MV for dashboards | With 100M rows and simple aggregations, direct query is fast enough on MoW | field |
