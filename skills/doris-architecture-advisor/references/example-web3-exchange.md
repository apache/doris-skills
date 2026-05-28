# Example: Web3 / Crypto Exchange — Real-time On-chain Analytics

## Scenario

- **Workload:** Centralized crypto exchange (CEX) + on-chain analytics across multiple blockchains
- **Data sources:** Order matching engine (internal DB), on-chain data services (blockchain nodes/APIs), Kafka streams, S3 historical archives
- **Data volume:** 50M+ trades/day, 100M+ on-chain events/day across 5+ chains, TB-scale daily
- **Query patterns:** Real-time trade analytics (swap, transfer, commission), asset custody monitoring, risk/AML detection, user wallet profiling, on-chain reporting (TVL, token metrics, NFT trends), marketing segmentation
- **Special requirements:** Multi-chain schema differences (VARIANT), sub-second trade queries at 1000+ QPS, address reputation label JOINs, session analysis for user flows

## Workload Classification

**Composite workload** — 6 sub-workloads:

| Sub-workload | Type | Decision pattern |
|-------------|------|-----------------|
| Trade/transaction detail (multi-chain) | Time-series (append-only) | DUPLICATE + VARIANT for chain-specific fields |
| Asset custody state (portfolio balances) | Mutable state | UNIQUE MoW + sequence_col on block_height |
| On-chain KPI dashboards (TVL, token metrics) | Pre-aggregation | AGGREGATE + async MV with 1-min refresh |
| Risk/AML detection | Log search + Ad-hoc | DUPLICATE + inverted index on address + contract |
| User wallet profiling (wide + tall table) | Point query + Segmentation | AGGREGATE wide table + BITMAP tall table |
| On-chain reporting (multi-dimensional) | Report analytics | Layered: raw detail → subject models → reports |

## Web3-specific Design Patterns

### Multi-chain schema with VARIANT
Different blockchains have different transaction fields. Use VARIANT for chain-specific data, typed columns for common fields:
- Common: `tx_hash`, `block_number`, `block_time`, `from_address`, `to_address`, `value`, `chain_id`
- Ethereum-specific: `gas_price`, `gas_used`, `input_data`
- Solana-specific: `compute_units`, `program_id`
- Store chain-specific fields in VARIANT column — 8x faster than JSON, auto schema evolution

### Address reputation labels for risk JOINs
- Dimension table of address labels (blacklist, whale, exchange, contract type)
- UNIQUE MoW with frequent updates as new labels are discovered
- JOIN with transaction detail for risk detection queries
- Consider colocation on `address` column for zero-shuffle JOINs

### TVL and token metrics: Async MV with partition_sync_limit
- Base: multi-chain transaction detail (10B+ rows)
- Async MV refreshes every 1-5 minutes with `partition_sync_limit` to process only recent partitions
- Pre-aggregate by protocol/token/chain/hour for dashboard queries
- Do NOT use sync MV (too much data for synchronous maintenance)

### Session analysis for user behavior flows
- Doris supports retention, funnel, and session analysis functions natively
- Track user paths: wallet creation → first swap → bridge usage → withdrawal
- Store as DUPLICATE event table, query with `window_funnel()` and `retention()`

### Wallet profiling: Wide + tall table pattern (same as retail CDP)
- Wide table: one row per wallet address, columns for each label (AGGREGATE + REPLACE_IF_NOT_NULL)
- Tall table: one row per label value, BITMAP stores wallet addresses (AGGREGATE + BITMAP_UNION)
- Wide for point queries ("show me this wallet's profile"), tall for segmentation ("find all whales on Ethereum")

## Architecture

```
On-chain Nodes / APIs        Ingestion              {{PRODUCT_NAME}}                           Applications
┌───────────────┐                                  ┌──────────────────────┐
│ Blockchain    │                                  │ Raw Detail           │
│ Event Streams │── Kafka → Flink ────────────────│  tx_events (DUP)     │──→ Trade Analytics
│ (ETH,BSC,SOL) │                                  │  + VARIANT for chain │──→ On-chain Reports
├───────────────┤                                  ├──────────────────────┤
│ Order Engine  │── Kafka → Routine Load ─────────│  trades (DUP)        │──→ Commission Calc
│ (internal)    │                                  │                      │──→ P&L Dashboard
├───────────────┤                                  ├──────────────────────┤
│ S3 Historical │── Broker Load (batch) ──────────│  Subject Models      │
│ (archive)     │                                  │  (async MV layer)    │──→ TVL / Token KPIs
└───────────────┘                                  ├──────────────────────┤
                                                   │  Custody State       │
                                                   │  (UNIQUE MoW)        │──→ Asset Monitoring
                                                   ├──────────────────────┤
                                                   │  Address Labels      │──→ Risk / AML
                                                   │  (UNIQUE MoW, dim)   │──→ Wallet Profiling
                                                   ├──────────────────────┤
                                                   │  User Segments       │──→ Marketing
                                                   │  (AGG + BITMAP)      │──→ Campaign Targeting
                                                   └──────────────────────┘
```

**Data modeling layers (from PDF):**
- Raw data: transaction detail (DUPLICATE), contract event detail, token asset snapshots
- Subject models: trade dimension model, contract dimension model, token granularity model
- Reports: contract call TOP10, daily active addresses, token holder distribution, cross-chain bridge flow trends

## Decision Provenance

| Decision | Source |
|----------|--------|
| VARIANT for multi-chain schema | `official` — different chains have different fields, 8x faster than JSON |
| DUPLICATE for transaction events | `official` — append-only on-chain events, fastest scan |
| UNIQUE MoW for custody balances | `official` — balance updates with sequence_col on block_height |
| Async MV for TVL/token metrics | `official` — 10B+ rows, partition_sync_limit for incremental refresh |
| BITMAP tall table for wallet segmentation | `official` — sub-second audience selection across millions of addresses |
| Inverted index for address/contract search | `official` — replaces Elasticsearch for on-chain address lookup |
| Window functions for session analysis | `official` — retention(), window_funnel() for user behavior flows |
| Kafka + Flink for on-chain ingestion | `derived` — standard Web3 data pipeline pattern |
| S3 Broker Load for historical backfill | `official` — batch import for multi-year blockchain archive |
| Colocation on address for risk JOINs | `derived` — zero-shuffle JOIN between tx detail and address labels |
