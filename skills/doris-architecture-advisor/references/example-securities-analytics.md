# Example: Securities & Fund Industry — Real-time Analytics Platform

## Scenario

- **Workload:** Securities firm building a unified real-time data warehouse replacing Impala + Kudu + ES + Greenplum
- **Data sources:** Trading system (Oracle), account system (MySQL), CRM (PG), market quotes (Kafka), app behavior logs (Kafka), external data lake (Hive/Iceberg)
- **Data volume:** 200 GB/day trading data, 500M+ behavior events/day, 10M customer profiles, 3+ years history in data lake
- **Query patterns:** Real-time KPI dashboards (sub-second), customer 360 point queries (<100ms at 10K QPS), compliance log search, ad-hoc portfolio analysis, cross-department analytics
- **Special requirements:** ODS → DWD → DWS → ADS warehouse layering, workload isolation between departments, hot/cold data tiering, BITMAP audience segmentation

## Workload Classification

**Composite workload** — 6 sub-workloads:

| Sub-workload | Type | Table(s) |
|-------------|------|----------|
| Trading detail (ODS/DWD) | CDC sync | `ods_trade_detail`, `dwd_trade_detail` |
| Customer profile (360 view) | Mutable state + Point query | `customer_profile` |
| Behavior events | Time-series / Log | `customer_events` |
| KPI dashboards (ADS) | Report / Pre-aggregation | `ads_revenue_daily`, `ads_aum_summary` |
| Compliance log search | Log search | `trade_audit_logs` |
| Historical data (lake) | Lakehouse federation | External catalog (Hive/Iceberg) |

## Sizing Recommendation

- **Total vCPU:** 64 vCPU total, 3 TB total cache
- **Hot data:** 1 year trading (~200 GB/day × 365 × 0.15 ZSTD = ~11 TB) + profiles (~50 GB) + events (~500M/day × 365 × 0.05 = ~9 TB)
- **Cache strategy:** Cache ≥50% of hot data. Set `file_cache_ttl_seconds` per table: dimension tables = 0 (forever), fact tables = 7776000 (90 days)
- **Cold data:** 3+ years in Hive/Iceberg, queried via Multi-Catalog with 10-20% latency overhead

## Architecture

```
Data Sources                    Data Collection          Real-time DW (Apache Doris)        Applications
┌──────────┐                                            ┌─────────────────────┐
│ Trading  │──── Flink CDC ──────────────────────────────│ ADS (Aggregate)     │──→ KPI Dashboards
│ (Oracle) │                                            │ ads_revenue_daily   │──→ Management Cockpit
├──────────┤                                            ├─────────────────────┤
│ Account  │──── Flink CDC ──────────────────────────────│ DWS (Duplicate)     │──→ Advisor Platform
│ (MySQL)  │                                            │ customer_profile    │──→ Wealth Management
├──────────┤                                            ├─────────────────────┤
│ CRM (PG) │──── Flink CDC ──────────────────────────────│ DWD (Unique MoW)    │──→ Risk Control
├──────────┤                                            │ dwd_trade_detail    │──→ Compliance Audit
│ Quotes   │──── Routine Load (Kafka) ──────────────────├─────────────────────┤
│ (Kafka)  │                                            │ ODS (Unique MoW)    │
├──────────┤                                            │ ods_trade_detail    │
│ App Logs │──── Routine Load (Kafka) ──────────────────├─────────────────────┤
│ (Kafka)  │                                            │ DIM (Unique MoW)    │
└──────────┘                                            │ dim_product         │
                                                        └────────┬────────────┘
Data Lake (Hive/Iceberg) ────── Multi-Catalog ───────────────────┘
                                (federated query, no data movement)
```

**Warehouse layering:**
- **ODS:** Raw data, UNIQUE KEY for dedup, Flink CDC for real-time sync
- **DWD:** Cleaned detail data, UNIQUE KEY for row-level updates, Doris SQL ETL for cleaning
- **DWS:** Wide tables joined from DWD + DIM, DUPLICATE for fastest scan, async MV for cross-table joins
- **ADS:** Pre-aggregated KPIs, AGGREGATE for auto-rollup, serves dashboards directly
- **DIM:** Dimension tables (products, branches, advisors), UNIQUE MoW for updates

## Table Designs

### 1. `ods_trade_detail` — ODS layer (CDC from trading system)

```sql
CREATE TABLE ods_trade_detail (
    trade_id       BIGINT        NOT NULL,
    trade_time     DATETIME(3)   NOT NULL,
    account_id     VARCHAR(32)   NOT NULL,
    update_time    DATETIME(3)   NOT NULL,
    symbol         VARCHAR(20)   NOT NULL,
    direction      VARCHAR(10),              -- BUY, SELL
    quantity       BIGINT,
    price          DECIMAL(18,4),
    amount         DECIMAL(18,2),
    status         VARCHAR(20),              -- pending, filled, cancelled
    channel        VARCHAR(20)               -- app, web, api
) ENGINE=OLAP
UNIQUE KEY(trade_id, trade_time)
PARTITION BY RANGE(trade_time) ()
DISTRIBUTED BY HASH(trade_id) BUCKETS 10    -- 200 GB/day × 0.15 = 30 GB ÷ 2 GB = ~15, round to 10 for initial
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "function_column.sequence_col" = "update_time",
    "replication_num" = "1"
);
-- UNIQUE MoW for ODS: prevents duplicate ingestion from Flink CDC replay
-- sequence_col: trade status updates (pending → filled → settled) arrive in order
-- PARTITION BY RANGE(trade_time): 200 GB/day exceeds 100GB threshold, daily partitions required
-- trade_time included in UNIQUE KEY: required when using PARTITION BY RANGE
```

### 2. `customer_profile` — Customer 360 (point query + BITMAP segmentation)

```sql
CREATE TABLE customer_profile (
    customer_id     VARCHAR(32)   NOT NULL,
    update_time     DATETIME(3)   NOT NULL,
    name            VARCHAR(100),
    risk_level      VARCHAR(10),             -- conservative, moderate, aggressive
    total_assets    DECIMAL(18,2),
    trading_freq    INT,                     -- trades per month
    product_pref    VARCHAR(200),            -- fund, stock, bond, etc.
    channel_pref    VARCHAR(50),
    advisor_id      VARCHAR(32),
    last_login      DATETIME,
    tags            VARCHAR(500)             -- comma-separated labels
) ENGINE=OLAP
UNIQUE KEY(customer_id)
DISTRIBUTED BY HASH(customer_id) BUCKETS 8  -- 10M customers × ~500 bytes = ~5 GB ÷ 2 GB = ~3, use 8 for distribution
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "store_row_column" = "true",
    "light_schema_change" = "true",
    "replication_num" = "1"
);
-- store_row_column: advisor lookup by customer_id in <100ms
-- Segmentation queries use standard SQL: WHERE risk_level = 'aggressive' AND total_assets > 1000000
```

### 3. `customer_events` — Behavior events (time-series)

```sql
CREATE TABLE customer_events (
    customer_id    VARCHAR(32)   NOT NULL,
    event_time     DATETIME(3)   NOT NULL,
    event_type     VARCHAR(50)   NOT NULL,   -- page_view, trade, login, product_click
    page_url       VARCHAR(500),
    product_id     VARCHAR(32),
    data           VARIANT,                  -- flexible event properties
    INDEX idx_event_type(event_type) USING INVERTED
) ENGINE=OLAP
DUPLICATE KEY(customer_id, event_time, event_type)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(customer_id) BUCKETS 8  -- 500M events/day × ~200 bytes = ~100 GB × 0.1 ZSTD = 10 GB ÷ 2 = 5, use 8
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-90",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",
    "compaction_policy" = "time_series",
    "replication_num" = "1"
);
```

### 4. `ads_revenue_daily` — ADS layer (pre-aggregated KPIs)

```sql
CREATE TABLE ads_revenue_daily (
    stat_date       DATE          NOT NULL,
    branch_id       VARCHAR(20)   NOT NULL,
    business_line   VARCHAR(30)   NOT NULL,  -- brokerage, wealth, investment_banking
    trade_count     BIGINT        SUM DEFAULT "0",
    trade_amount    DECIMAL(18,2) SUM DEFAULT "0",
    commission      DECIMAL(18,2) SUM DEFAULT "0",
    new_customers   BIGINT        SUM DEFAULT "0",
    active_customers BITMAP       BITMAP_UNION
) ENGINE=OLAP
AGGREGATE KEY(stat_date, branch_id, business_line)
PARTITION BY RANGE(stat_date) ()
DISTRIBUTED BY HASH(branch_id) BUCKETS 3
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-24",
    "dynamic_partition.end" = "1",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
-- AGGREGATE: dashboard queries read pre-computed KPIs, no scanning detail data
-- BITMAP_UNION: exact distinct active customer count per branch per day
```

### 5. `trade_audit_logs` — Compliance log search

```sql
CREATE TABLE trade_audit_logs (
    log_time       DATETIME      NOT NULL,
    account_id     VARCHAR(32)   NOT NULL,
    action         VARCHAR(50)   NOT NULL,
    ip_address     VARCHAR(45),
    error_code     VARCHAR(20),
    message        TEXT,
    INDEX idx_msg(message) USING INVERTED PROPERTIES("parser" = "unicode"),
    INDEX idx_action(action) USING INVERTED,
    INDEX idx_error(error_code) USING INVERTED
) ENGINE=OLAP
DUPLICATE KEY(log_time, account_id, action)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(account_id) BUCKETS 5   -- audit logs lower volume than trading
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-36",       -- 3-year compliance retention
    "dynamic_partition.end" = "1",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",
    "replication_num" = "1"
);
-- 3-year retention for compliance audit
-- Inverted index on message + error_code for pattern detection
```

### 6. Lakehouse federation (no table creation — uses Multi-Catalog)

```sql
-- Access 3+ year historical data in Hive/Iceberg without data movement:
CREATE CATALOG hive_catalog PROPERTIES (
    "type" = "hms",
    "hive.metastore.uris" = "thrift://metastore:9083"
);

-- Query historical data directly:
SELECT * FROM hive_catalog.trading_db.trade_detail_history
WHERE trade_date BETWEEN '2022-01-01' AND '2023-12-31';

-- Accelerate with async MV if queries are repeated:
CREATE MATERIALIZED VIEW mv_historical_summary
REFRESH AUTO ON SCHEDULE EVERY 1 DAY
AS SELECT trade_date, symbol, SUM(amount) AS total_amount
FROM hive_catalog.trading_db.trade_detail_history
GROUP BY trade_date, symbol;
```

## Workload Isolation

For multi-department access (operations, risk, marketing, investment, customer service, finance), use Workload Groups:

```sql
-- Create isolated workload groups per department
CREATE WORKLOAD GROUP wg_risk PROPERTIES ("cpu_share" = "30", "memory_limit" = "30%");
CREATE WORKLOAD GROUP wg_marketing PROPERTIES ("cpu_share" = "20", "memory_limit" = "20%");
CREATE WORKLOAD GROUP wg_advisor PROPERTIES ("cpu_share" = "25", "memory_limit" = "25%");

-- Assign users to workload groups
SET PROPERTY FOR 'risk_team' 'default_workload_group' = 'wg_risk';
```

## Decision Provenance

| Decision | Source |
|----------|--------|
| ODS/DWD with UNIQUE MoW | `official` — CDC dedup, row-level updates for status changes |
| DWS with DUPLICATE | `derived` — wide table joins produce read-optimized scan layer |
| ADS with AGGREGATE + BITMAP | `official` — auto-rollup for dashboards, exact distinct counts |
| store_row_column for customer_profile | `official` — sub-100ms advisor lookups |
| Multi-Catalog for lakehouse | `official` — federated query on Hive/Iceberg without data movement |
| Async MV for layer-to-layer ETL | `official` — scheduled refresh replaces Spark/Hive batch ETL |
| Workload Group for dept isolation | `official` — CPU/memory isolation between departments |
| Inverted index on audit logs | `official` — compliance pattern search on error_code + message |
| ZSTD on events and logs | `derived` — high redundancy in behavioral and audit data |
| 3-year partition retention for compliance | `field` — regulatory requirement; adjust per jurisdiction |
| 64 vCPU / 3 TB cache | `field` — ~75% accuracy; confirm with Apache Doris SA |
