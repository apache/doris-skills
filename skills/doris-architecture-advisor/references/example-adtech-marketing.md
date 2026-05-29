# Example: Programmatic Digital Marketing / AdTech

## Scenario

- **Workload:** Global DSP/ADX platform serving ads across Google, Meta, TikTok, Snapchat in 200+ countries
- **Data sources:** SSP ad requests (Kafka), RTB bid logs, impression/click/conversion logs, user behavior (SDK), third-party attribution (AppsFlyer), ad creatives (images/video/text from S3)
- **Data volume:** 10B+ ad requests/day, hundreds of TB daily, PB-scale total
- **Query patterns:** Millisecond user profile lookups for real-time bidding (RTB), second-level campaign KPI dashboards (CTR, CVR, ROI), advertiser self-service reporting, creative performance analysis, fraud detection
- **Special requirements:** Dual-path architecture (millisecond serving + second-level analytics), multi-modal data (structured + semi-structured JSON + unstructured creative assets), VARIANT for cross-platform schema differences, vector index for creative similarity search, global multi-region deployment

## Workload Classification

**Composite workload** — 6 sub-workloads:

| Sub-workload | Type | Decision pattern |
|-------------|------|-----------------|
| User profile labels (RTB serving) | Point query | UNIQUE MoW + store_row_column for millisecond lookups during bidding |
| Ad delivery detail logs | Time-series (append-only) | DUPLICATE + RANGE partition, DWD wide table joining impression+click+conversion |
| Campaign KPI dashboards | Pre-aggregation | AGGREGATE + sync/async MV for CTR/CVR/ROI rollup |
| Advertiser self-service reports | Report + Ad-hoc | Query on DWS/ADS layer with advertiser_id filter + workload isolation |
| Creative metadata analysis | Report + Search | VARIANT for cross-platform JSON metadata + vector index for similarity |
| Traffic quality / fraud detection | Log search | DUPLICATE + inverted index + sync MV for real-time fraud scoring |

## AdTech-specific Design Patterns

### Dual-path architecture: RTB serving + analytics
The core challenge: the bidding engine needs millisecond access to user profiles, while analytics needs second-level aggregation on billions of logs.

- **Serving path (millisecond):** User profile labels stored in UNIQUE MoW with `store_row_column = true`. Bidding engine queries by user_id via PreparedStatement at 30K+ QPS. Replaces Redis for profile lookups.
- **Analytics path (second-level):** Impression/click/conversion logs stored in DUPLICATE model. Sync MV for real-time CTR/CVR. Async MV for campaign-level aggregations refreshed every 1-5 minutes.
- **Bridge:** Flink computes real-time features (CTR prediction, budget deduction, frequency cap) and writes back to both the serving table and the analytics table.

### Multi-modal data storage
- **Structured:** Channel, device, advertiser master data — standard typed columns (Date, String, Int)
- **Semi-structured:** User-Agent, request body, creative tags — VARIANT type + inverted index for full-text search
- **Unstructured:** Creative assets (images, video, text) — vectorized via embedding, stored with vector index for similarity search (find creatives similar to top performers)

### DWD + DWS + ADS for ad analytics
- **DWD (detail):** Wide table joining ad request + impression + click + conversion logs. Supports multi-dimensional drill-down and attribution analysis.
- **DWS (summary):** Sync MV for real-time CTR/CVR computation. Async MV for campaign/channel/creative-level rollups.
- **ADS (application):** Pre-aggregated KPIs by advertiser × campaign × day. Sub-second dashboard queries for 10,000+ concurrent advertisers.

### Platform consolidation: Redis + MySQL + HBase + Hive → Apache Doris
| Old system | Role | Apache Doris replacement |
|-----------|------|-------------------|
| Redis | RTB user profile serving | UNIQUE MoW + store_row_column (30K QPS, <10ms) |
| MySQL | Campaign management | Flink CDC → UNIQUE MoW |
| HBase | User behavior history | DUPLICATE + partition + time_series compaction |
| Hive/Spark | Offline attribution | Async MV + Multi-Catalog for lakehouse |

Result: TCO reduction 30-50%, unified data layer, one SQL interface.

### Cross-border / multi-region
- Apache Doris cloud mode supports AWS, GCP, Azure deployment in any region
- SAAS and BYOC models for different compliance requirements (GDPR, CCPA)
- Multi-currency conversion handled in DWS layer via dimension table JOINs
- Each region can have its own compute group with workload isolation

## Decision Provenance

| Decision | Source |
|----------|--------|
| UNIQUE MoW + store_row_column for RTB serving | `official` — millisecond point queries replace Redis |
| DUPLICATE for ad log detail | `official` — append-only impression/click/conversion events |
| Sync MV for real-time CTR/CVR | `official` — zero-lag aggregation on DWD detail table |
| VARIANT for cross-platform JSON | `official` — different ad platforms have different request schemas |
| Vector index for creative similarity | `official` — HNSW for ANN search on creative embeddings |
| Workload Groups for advertiser isolation | `official` — 10K concurrent advertisers, prevent cross-impact |
| Dual-path (serving + analytics) | `derived` — same Apache Doris instance serves both RTB and dashboard workloads |
| Multi-Catalog for offline attribution | `official` — Hive/S3 data queried without movement |
