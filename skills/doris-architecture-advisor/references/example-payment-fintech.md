# Example: Payment / Fintech — Real-time Transaction Analytics Platform

## Scenario

- **Workload:** Payment company processing millions of daily transactions across acquiring, settlement, risk control, and merchant services
- **Data sources:** Transaction DB (acquiring records, clearing, refunds), user behavior (app events, web payment trails), risk data (device fingerprints, IP, blacklists), account data (balances, card bindings), external (credit scoring, crawled data)
- **Data volume:** 100M+ transactions/day, billions of rows per table (100+ columns for acquiring), 10-100TB/day logs
- **Query patterns:** Real-time transaction dashboard, merchant reconciliation (P99 <2s at millions of daily queries), acquiring point lookups (10K+ QPS, millisecond, composite key), risk detection (multi-dimensional JOINs), security log search
- **Special requirements:** Partial column updates (transaction status changes), row-column hybrid storage for acquiring (point lookup + analytics on same table), replacing Lambda architecture (Hive+HBase+ES+Oracle→{{PRODUCT_NAME}})

## Workload Classification

**Composite workload** — 6 sub-workloads:

| Sub-workload | Type | Decision pattern |
|-------------|------|-----------------|
| Transaction detail (acquiring) | CDC + Point query | UNIQUE MoW + store_row_column + composite key |
| Transaction status updates | Mutable state | UNIQUE MoW + partial column update (session variable) |
| Real-time KPI dashboards | Pre-aggregation | AGGREGATE or async MV |
| Merchant reconciliation | Report + Point query | Query on detail tables with merchant_id filter |
| Risk detection | Ad-hoc + Log search | Multi-table JOIN with inverted index on risk labels |
| Security/system logs | Log search | DUPLICATE + inverted index + ZSTD, replacing ES |

## Payment-specific Design Patterns

### Partial column update for transaction lifecycle
Transaction status evolves: created → authorized → captured → settled → refunded. Each step updates only a few columns. Use UNIQUE MoW with partial update at write time (session variable, not table property):
```
SET enable_unique_key_partial_update = true;
INSERT INTO transactions (tx_id, tx_time, status, settled_amount, settle_time) VALUES (...);
```

### Acquiring table: row-column hybrid for dual workload
Tables with 100+ columns serving both point lookups (bank queries by composite key) and analytical queries (regional aggregations):
- `store_row_column = "true"` enables row-store for point lookups (millisecond, single I/O)
- Columnar storage still used for analytical scans (best of both worlds)
- Inverted index on frequently filtered columns (merchant_id, status, card_type)
- BloomFilter via `bloom_filter_columns` property for high-cardinality equality filters

### Merchant reconciliation: high-concurrency multi-tenant queries
- 500K merchants each querying their own data
- Partition by date, bucket by merchant_id — queries prune to relevant tablets
- P99 < 2s at millions of daily queries
- Async MV for pre-computed daily/monthly settlement summaries

### Log platform replacing Elasticsearch
- 10-100TB/day log volume from security devices, middleware, business systems
- ZSTD compression: 60-80% storage savings vs ES
- Inverted index with unicode parser for full-text search
- VARIANT for semi-structured JSON logs
- Cold data tiering to S3 via cooldown_ttl
- time_series compaction for sustained GB/s write with sub-second flush

### Platform consolidation: Lambda → unified architecture
Replacing 6 systems (Hive + Spark + HBase + ES + Oracle + TiDB) with one {{PRODUCT_NAME}} instance:

| Old system | Role | {{PRODUCT_NAME}} replacement |
|-----------|------|-------------------|
| Hive + Spark | Batch ETL | Async MV + INSERT INTO SELECT |
| HBase | Key-value lookups | UNIQUE MoW + store_row_column |
| Elasticsearch | Log search, text search | Inverted index + VARIANT |
| Oracle | Reports, reconciliation | MPP engine, sub-second on pre-aggregated tables |
| TiDB / MySQL | Transaction queries | Flink CDC → UNIQUE MoW with real-time sync |

Real customer result (Lakala, stock code 300773): replaced Lambda architecture, daily query volume exceeds 1M, query performance improved significantly.

## Decision Provenance

| Decision | Source |
|----------|--------|
| UNIQUE MoW for transaction detail | `official` — supports upsert for status lifecycle |
| Partial column update via session variable | `official` — `SET enable_unique_key_partial_update = true` at write time, NOT as table property |
| store_row_column for acquiring tables | `official` — dual workload: point lookup + analytics |
| Inverted index replacing ES | `official` — full-text MATCH with unicode parser |
| ZSTD + cooldown_ttl for logs | `official` — 60-80% storage savings, cold tier to S3 |
| VARIANT for log schema flexibility | `official` — semi-structured JSON with auto schema evolution |
| Async MV for reconciliation summaries | `official` — pre-computed daily/monthly rollups |
| bloom_filter_columns for composite key | `official` — high-cardinality point lookup acceleration |
| time_series compaction for log ingestion | `official` — GB/s sustained write, DUPLICATE only |
