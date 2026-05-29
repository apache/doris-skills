# Example: Gaming Industry — Real-time Player Analytics Platform

## Scenario

- **Workload:** Mobile/PC game with millions of DAU, real-time operations, player profiling, behavior analysis
- **Data sources:** MySQL (operational data), Kafka (player behavior events, real-time tags), Hive/S3 (offline behavior, offline tags), third-party (ad attribution, channel data)
- **Data volume:** 2B+ behavior events/day (TB-scale daily), 50M+ registered users, hundreds of TB total
- **Query patterns:** Real-time KPI dashboards (DAU, retention, ARPU), player profiling with BITMAP segmentation, retention/funnel analysis, anomaly detection for anti-cheat, Agentic NL2SQL analytics
- **Special requirements:** Sub-second dashboard refresh, 1-10s for complex behavioral queries, real-time tag updates within 10 seconds, lakehouse integration for offline data

## Workload Classification

**Composite workload** — 5 sub-workloads:

| Sub-workload | Type | Decision pattern |
|-------------|------|-----------------|
| Player behavior events | Time-series (append-only) | DUPLICATE + RANGE partition by day + time_series compaction |
| Player profiles (wide + tall table) | Point query + Segmentation | AGGREGATE wide table + BITMAP tall table (same as retail CDP) |
| Game KPI dashboards | Pre-aggregation | AGGREGATE + sync/async MV |
| Anti-cheat anomaly detection | Log search + Ad-hoc | DUPLICATE + inverted index on player_id + event_type |
| Agentic analytics (NL2SQL) | Ad-hoc + Report | All tables queryable via MCP, natural language interface |

## Gaming-specific Design Patterns

### Retention and funnel analysis
Doris has built-in `retention()` and `window_funnel()` functions for gaming analytics:
- Retention: Day 1/7/30 retention by cohort (registration date × source channel)
- Funnel: tutorial_complete → first_battle → first_purchase → first_social_interaction
- Session analysis: average session length, sessions per day, inter-session gap

### Player profiling: Wide + tall table (same pattern as retail/web3)
- Wide table: one row per player, columns for each tag (AGGREGATE + REPLACE_IF_NOT_NULL)
- Tall table: one row per tag value, BITMAP stores player IDs (AGGREGATE + BITMAP_UNION)
- Real-time tag updates via Kafka → Flink → partial update on wide table
- Offline tags from Hive/S3 via Catalog or Broker Load

### Agentic analytics platform (NL2SQL + MCP)
- Apache Doris as the data layer for AI Agent applications
- MCP (Model Context Protocol) interface for AI agents to query data
- Business domain agents: User Behavior Agent, Operations Agent, A/B Testing Agent, Retention Agent
- Natural language → SQL → Apache Doris → visualization, no coding required

### Anti-cheat: Anomaly detection on behavior events
- DUPLICATE model for raw behavior events
- Inverted index on event_type, player_id for fast filtering
- Window functions to detect: unusual event frequency, impossible timing (1000 battles in 1 hour), suspicious gold transfer patterns
- Real-time alerting via scheduled queries or async MV

### Lakehouse integration for offline data
- Real-time: MySQL → Flink CDC → Apache Doris (operational data)
- Real-time: Kafka → Flink → Apache Doris (behavior events, real-time tags)
- Offline: Hive/S3 → Catalog (lakehouse federation, no data movement)
- Warehouse layers: ODS → DWD (async MV / ETL SQL) → DWS (async MV) → ADS

## Decision Provenance

| Decision | Source |
|----------|--------|
| DUPLICATE for behavior events | `official` — append-only, fastest scan for retention/funnel queries |
| retention() and window_funnel() | `official` — built-in Doris functions for gaming analytics |
| BITMAP for player segmentation | `official` — sub-second audience selection across 50M players |
| MCP interface for Agentic analytics | `official` — Apache Doris supports MCP for AI agent integration |
| Sync MV for real-time KPI (1-3s) | `official` — zero-lag aggregation for dashboard metrics |
| Async MV for near-real-time (1-10min) | `official` — incremental refresh for complex multi-table analytics |
| Multi-Catalog for offline data | `official` — Hive/Iceberg/Paimon federation without data movement |
