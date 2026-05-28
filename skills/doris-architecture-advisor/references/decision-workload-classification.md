# Workload Classification

Identify the user's workload type before any sizing or DDL. Many real-world systems are composite — decompose into sub-workloads and design a table per sub-workload.

## 6 Workload Types

### 1. Report Analytics
Multi-dimensional statistics and reporting on wide tables.
- **Signals:** dashboard, report, BI tool, Grafana, Superset, aggregation queries, GROUP BY
- **Data shape:** Pre-joined wide tables, mostly read, moderate write
- **Query pattern:** Fixed-dimension GROUP BY, filtered aggregations, low latency
- **Typical model:** DUPLICATE (flexible ad-hoc) or AGGREGATE (pre-computed metrics)

### 2. Ad-hoc Analytics
Exploratory analysis on detail data, often with multi-table joins.
- **Signals:** data exploration, data science, Jupyter, "we don't know the queries yet", flexible analysis
- **Data shape:** Detail-level fact tables + dimension tables, star/snowflake schema
- **Query pattern:** Unpredictable JOINs, variable filters, moderate latency (1-3s OK)
- **Typical model:** DUPLICATE for facts, DUPLICATE/UNIQUE for dimensions

### 3. Lakehouse Federation
Interactive analysis on external data lake data (Hive, Iceberg, Hudi, Paimon).
- **Signals:** data lake, Iceberg, Hudi, S3, external table, federated query, Trino replacement
- **Data shape:** External catalogs + optional internal materialized tables
- **Query pattern:** Cross-source JOINs, moderate latency (1-8s)
- **Typical model:** External catalog + async MV for hot data acceleration

### 4. Log Storage & Search
High-volume log ingestion with full-text search and time-bounded queries.
- **Signals:** logs, Elasticsearch replacement, log search, keyword search, MATCH, observability, traces, error tracking
- **Data shape:** Append-only, semi-structured (text + structured fields), high volume
- **Query pattern:** Time-range + keyword search, aggregated error rates, trace correlation
- **Typical model:** DUPLICATE + inverted index + ZSTD compression

### 5. Real-time Data Warehouse / ETL
Incremental data processing and transformation within {{PRODUCT_NAME}}.
- **Signals:** ETL, ELT, data pipeline, dbt, materialized view, incremental processing, ODS/DWD/DWS/ADS layers
- **Data shape:** Layered warehouse model (ODS → DWD → DWS → ADS)
- **Query pattern:** Scheduled transformations, INSERT INTO SELECT, async MV refresh
- **Typical model:** Mix of DUPLICATE (ODS) + AGGREGATE (DWS) + async MV (cross-layer)

### 6. Point Query Service
High-concurrency, low-latency key-value lookups served via API.
- **Signals:** API serving, user profile lookup, key-value, sub-100ms, high QPS (>10K), PreparedStatement
- **Data shape:** Wide row, single-key lookup, moderate updates
- **Query pattern:** `SELECT * FROM t WHERE id = ?`, single-row result
- **Typical model:** UNIQUE MoW + `store_row_column = "true"` + BloomFilter

## Composite Workload Examples

| User scenario | Sub-workloads | Tables needed |
|---------------|---------------|---------------|
| IoT platform | Time-series (readings) + Mutable state (device shadow) + Logs (device logs) + Report (dashboards) + Point query (device status API) | 4-5 tables |
| E-commerce analytics | CDC sync (orders) + Report (revenue dashboards) + Ad-hoc (customer behavior) | 2-3 tables |
| Observability platform | Log search (logs) + Time-series (traces) + Pre-agg metrics (metrics) | 3 tables |
| Fleet / vehicle tracking | Time-series (GPS events) + Mutable state (vehicle status) + Report (route analytics) | 3 tables |

## Cross-cutting Patterns

These patterns apply across multiple workload types:

### Warehouse Layering (ODS → DWD → DWS → ADS)
When building a real-time data warehouse, use different data models per layer:
- **ODS (raw):** UNIQUE MoW — dedup on CDC replay. **If partitioned by time, the time column MUST be in UNIQUE KEY:** `UNIQUE KEY(id, event_time) PARTITION BY RANGE(event_time)`
- **DWD (detail):** UNIQUE MoW — cleaned detail data, row-level updates. Same rule: partition column in key
- **DWS (summary):** DUPLICATE — wide tables from joins, fastest scan for analytics
- **ADS (application):** AGGREGATE — pre-computed KPIs, auto-rollup on ingest
- **DIM (dimension):** UNIQUE MoW — slowly changing dimensions with updates
- Layer-to-layer ETL via async MV or scheduled `INSERT INTO SELECT`

### Workload Isolation (Multi-department / Multi-tenant)
When different teams share the same cluster:
- Use **Workload Groups** to isolate CPU/memory per department
- Prevents risk team's heavy queries from impacting advisor dashboards
- `CREATE WORKLOAD GROUP wg_risk PROPERTIES ("cpu_share"="30", "memory_limit"="30%")`

### Lakehouse Federation (Hot/Cold Tiering)
When historical data lives in a data lake (Hive/Iceberg/Hudi):
- Hot data (recent 1 year): stored in {{PRODUCT_NAME}} for sub-second queries
- Cold data (3+ years): stays in data lake, queried via Multi-Catalog
- Accelerate repeated lake queries with async MV
- `file_cache_ttl_seconds` controls per-table cache lifetime

## Discovery Questions

If the workload type is unclear, ask:

1. **Data mutability:** Is data append-only, or do you need to update/delete rows?
2. **Write volume:** How much data per day? How many rows per second?
3. **Query pattern:** Fixed reports, or ad-hoc exploration? Single-row lookups or scans?
4. **Latency target:** Sub-100ms (point query), sub-second (report), 1-3s (ad-hoc)?
5. **Retention:** How long do you keep data? Is there a hot/cold boundary?
