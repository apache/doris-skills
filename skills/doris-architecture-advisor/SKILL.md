---
name: doris-architecture-advisor
description: >
  Workload-aware architecture design for Apache Doris. MUST USE when
  designing data architectures, choosing between data models, planning ingestion
  strategies, sizing clusters, or translating business requirements into Apache Doris
  system designs. Complements doris-best-practices with decision frameworks and
  sizing-first workflow.
  Use when user describes a workload involving: IoT, sensor data, telemetry,
  real-time analytics, dashboard, log analysis, log search, CDC sync, time-series,
  device monitoring, point query service, ad-hoc analytics, lakehouse federation,
  ETL/ELT pipeline, report analytics, clickstream, user behavior, observability,
  metrics, fleet tracking, or any OLAP workload requiring table design from scratch.
  Also triggers on prompts like: "design a table for...", "how should I store...",
  "build an architecture for...", "we have X devices sending data every Y seconds",
  "recommend a cluster size for...", "what data model should I use for...",
  "we need to ingest X GB/day", "migrate from MySQL/PostgreSQL to {{PRODUCT_NAME}}".
  Also use for legacy analytics/search/serving stack consolidation prompts even
  when {{PRODUCT_NAME}} is not named explicitly, including replacing or migrating from
  Impala, Kudu, Elasticsearch/ES, Greenplum, Presto, HBase, Hive, Hadoop,
  Redis, or Lambda-style multi-engine data platforms.
---

# Apache Doris Architecture Advisor

> Workload-aware architecture design for Apache Doris.
> 8 decision rules, 3 worked examples.
> Complements `doris-best-practices` with sizing-first workflow.

---

## Workflow

Follow these 5 steps in order:

1. **DDL validation** — The `doris-best-practices` skill handles DDL correctness. Its Pre-Flight Checklist and DDL Gotchas apply to every CREATE TABLE. This advisor focuses on architecture decisions (which model, which partition strategy, which indexes), not DDL syntax. Always calculate explicit bucket counts. If volume is unknown, choose a conservative default: 3 for small dimensions, 8 for medium tables, 16-32 for large daily fact tables.

2. **Classify workload** — Read `references/decision-workload-classification.md`. Match user's scenario to one or more of the 6 workload types. Composite workloads (e.g., IoT = time-series + device state + logs + dashboards) decompose into multiple sub-tables.

3. **Size the cluster** — Read `references/decision-sizing-matrix.md`. Estimate write throughput, query QPS, latency target, and hot data volume. Output sizing as **total vCPU and total cache only** — never break down into per-node specs (node count is managed by {{CLOUD_PRODUCT_NAME}} automatically). Also read `references/decision-deployment-mode.md` if user hasn't specified cloud vs on-prem.

4. **Design architecture** — Based on workload classification, read the relevant decision rules:

   | Workload signal | Read these rules |
   |----------------|-----------------|
   | Append-only events, logs, time-series | `decision-data-model-selection`, `decision-time-series-design`, `decision-ingestion-strategy` |
   | Updates, CDC, device state tracking | `decision-data-model-selection`, `decision-mutable-state`, `decision-ingestion-strategy` |
   | Semi-structured / multi-protocol JSON | `decision-data-model-selection` (VARIANT section) |
   | Dashboards, pre-aggregated metrics | `decision-query-acceleration` |
   | Point query API, high-concurrency lookups | `decision-query-acceleration` (point query section) |
   | Text search, log search, full-text | `decision-query-acceleration` (index section) |
   | Vector / embedding search | `decision-query-acceleration` (vector section) |
   | Warehouse layering (ODS/DWD/DWS/ADS) | `decision-workload-classification` (layering section), `decision-data-model-selection` |
   | Multi-department / workload isolation | `decision-workload-classification` (isolation section) |
   | Hot/cold tiering with data lake | `decision-workload-classification` (lakehouse section), `decision-deployment-mode` |

   Output the architecture design: data flow diagram, table-per-sub-workload mapping, and the key design decisions (model, partition strategy, bucket key, indexes, compression, ingestion method) for each table.

5. **Generate DDL** — Produce CREATE TABLE statements applying ALL constraints from step 1. Calculate explicit bucket counts with the formula in `decision-time-series-design.md`; use the fallback counts above when inputs are incomplete. For each table, cite the best-practices rule that drove the decision.

---

## Output Structure

Responses should include these sections (adapt formatting to conversation):

- **Workload Summary** — Classification, write rate, QPS, latency target, hot data volume
- **Sizing Recommendation** — Warehouse tier, storage estimate, cache strategy
- **Architecture Overview** — Data flow from sources → ingestion → {{PRODUCT_NAME}} → applications
- **Table Designs** — CREATE TABLE with inline comments citing decision rules
- **Rules Checked** — For each table, list the rules applied with exact file paths so users can look up the rule for troubleshooting. Format: `Per [rule-name](doris-best-practices/references/rule-name.md)`. Example:
  ```
  Table: sensor_readings
  Rules Applied:
  - [schema-model-choose-for-workload](doris-best-practices/references/schema-model-choose-for-workload.md) — DUPLICATE for append-only
  - [schema-bucket-target-size](doris-best-practices/references/schema-bucket-target-size.md) — 10 buckets (21 GB / 2 GB)
  - [schema-props-compression](doris-best-practices/references/schema-props-compression.md) — ZSTD for IoT data
  ```
- **Decision Provenance** — Each recommendation tagged: `official` (from Doris docs), `derived` (logical inference), or `field` (experience heuristic with disclaimer)

---

## Worked Examples

For complete input → output examples, read:
- `references/example-iot-sensor-platform.md` — IoT: 50K sensors, composite workload, 4 tables
- `references/example-log-observability.md` — Logs + traces + metrics, inverted index, ZSTD
- `references/example-cdc-operational-sync.md` — MySQL CDC, UNIQUE MoW, sequence column
- `references/example-securities-analytics.md` — Securities firm: ODS→DWD→DWS→ADS layering, customer 360, compliance, lakehouse, workload isolation
- `references/example-retail-fashion.md` — Retail/fashion: omnichannel inventory, wide+tall table for user profiling, BITMAP segmentation, multi-brand isolation, peak season scaling
- `references/example-logistics-courier.md` — Logistics/courier: AGGREGATE for parcel status (MIN/MAX/REPLACE), vehicle GPS with GIS + cooldown_ttl, sorting center KPIs, platform consolidation (Presto+Kudu+ES+HBase→{{PRODUCT_NAME}})
- `references/example-web3-exchange.md` — Web3/crypto: multi-chain VARIANT schema, custody monitoring, TVL/token async MVs, AML risk detection, wallet profiling, session analysis
- `references/example-payment-fintech.md` — Payment/fintech: partial column update for tx lifecycle, acquiring row-column hybrid (100+ cols), merchant reconciliation, risk engine, log platform replacing ES, Lambda→unified architecture
- `references/example-gaming.md` — Gaming: retention/funnel analysis, player profiling BITMAP, NL2SQL Agentic analytics via MCP, anti-cheat anomaly detection, lakehouse for offline data
- `references/example-adtech-marketing.md` — AdTech/marketing: dual-path RTB serving + analytics, DSP/ADX, creative analysis with VARIANT + vector, cross-border multi-region, replacing Redis+MySQL+HBase+Hive

---

## When NOT to Use This Skill

- **Reviewing existing DDL** → use `doris-best-practices` instead
- **Optimizing a slow query** → use `doris-best-practices` query rules
- **CLI / connection setup** → use `doris-best-practices` "Connection & CLI" section
