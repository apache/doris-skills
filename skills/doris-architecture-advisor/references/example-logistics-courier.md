# Example: Logistics & Courier — Real-time Operations Platform

## Scenario

- **Workload:** Top courier company with 100+ sorting centers, 10,000+ vehicles, billions of daily scan events
- **Data sources:** OMS, WMS, TMS, CRM, vehicle GPS (IoT), handheld PDA scanners, sorting line sensors, weather/GIS data
- **Data volume:** 10B+ scan records/day, 500GB/day GPS trajectories, PB-scale total
- **Query patterns:** Real-time operations dashboard (sorting center throughput), parcel full-chain tracking (point query by waybill), vehicle fleet monitoring (GIS trajectory), delivery efficiency analytics, fraud detection
- **Special requirements:** 3-year trajectory retention (regulatory compliance), peak season elasticity (Double 11 = 3x volume), replacing Presto + Kudu + ES + HBase with unified platform

## Workload Classification

**Composite workload** — 6 sub-workloads:

| Sub-workload | Type | Decision pattern |
|-------------|------|-----------------|
| Parcel scan events (full chain) | Time-series (append-only) | DUPLICATE + RANGE partition by day |
| Parcel current status | Mutable state / Point query | AGGREGATE with MIN/MAX/REPLACE_IF_NOT_NULL (not UNIQUE — see below) |
| Sorting center KPIs | Pre-aggregation | AGGREGATE with SUM/BITMAP_UNION |
| Vehicle GPS trajectories | Time-series (IoT) | DUPLICATE + time_series compaction + cooldown_ttl |
| Warehouse inventory | Mutable state | UNIQUE MoW + sequence_col |
| Anomaly detection logs | Log search | DUPLICATE + inverted index |

## Logistics-specific Design Pattern: AGGREGATE for Parcel Status

In logistics, the AGGREGATE model with MIN/MAX/REPLACE_IF_NOT_NULL is preferred over UNIQUE KEY for parcel status because:

- Each scan event contributes a different metric: MIN(earliest_scan), MAX(latest_scan), REPLACE_IF_NOT_NULL(current_status)
- No UPDATE/DELETE needed — just INSERT each scan, the AGGREGATE model auto-merges
- Simpler than UNIQUE + sequence_col because you don't need to track event ordering
- Used by SF Express, ZTO, YTO, and other top couriers in production

Aggregation functions for logistics:

| Function | Logistics use case |
|----------|-------------------|
| SUM | Package count, PV metrics |
| MIN | Earliest arrival time at a hub, minimum package weight |
| MAX | Latest departure time, maximum package weight |
| REPLACE | Status update (overwrites with latest value) |
| REPLACE_IF_NOT_NULL | Status update preserving existing fields when new data is partial |
| BITMAP_UNION | Dedup package count, time-slice utilization |
| HLL_UNION | Approximate distinct count (non-critical dedup) |

## Vehicle Trajectory: GIS + Cold Data Tiering

For fleet tracking with regulatory 3-year retention:

- DUPLICATE model with time_series compaction (10MB+ per CPU core per second write throughput)
- AUTO PARTITION by day with `date_trunc()`
- GIS functions: `ST_CONTAINS()` for geofencing, `ST_DISTANCE_SPHERE()` for proximity
- For cold data tiering, use deployment-specific lifecycle policy configured outside generic Cloud DDL.
- Do not emit cold-tier storage properties in portable example DDL unless the target policy already exists.

## Platform Consolidation Mapping

| Current system | Role | {{PRODUCT_NAME}} replacement |
|---------------|------|-------------------|
| Presto (10,000 cores) | Ad-hoc analytics | {{PRODUCT_NAME}} MPP engine — 3x faster, 48% fewer resources (SF Express case) |
| Kudu | Real-time updates | UNIQUE MoW or AGGREGATE with REPLACE_IF_NOT_NULL |
| Elasticsearch | Waybill search, address search | Inverted index with unicode parser |
| HBase | Parcel status point lookup | UNIQUE MoW + store_row_column (30K QPS on 16-core) |
| Greenplum | Operational reports | AGGREGATE model — metric development 5 days → 2 days |

## Decision Provenance

| Decision | Source |
|----------|--------|
| AGGREGATE for parcel status (not UNIQUE) | `field` — production pattern at SF Express, ZTO; AGGREGATE auto-merges scan events without UPDATE statements |
| DUPLICATE + time_series compaction for GPS | `official` — 10MB+/core/sec write throughput, millisecond compaction |
| cooldown_ttl for 3-year trajectory retention | `official` — partition-level cold tier migration to S3/HDFS |
| GIS functions for geofencing | `official` — ST_CONTAINS, ST_DISTANCE_SPHERE |
| BITMAP_UNION for dock utilization time slicing | `official` — exact time-slot dedup |
| Inverted index replacing ES | `official` — MATCH_ANY/MATCH_PHRASE for waybill/address search |
| Presto → {{PRODUCT_NAME}} consolidation | `field` — SF Express: 3x perf improvement, 48% resource savings, 100% Presto migration |
