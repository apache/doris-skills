# Query Acceleration

Covers materialized views, indexes, point query optimization, and caching.

Reference: [Sync MV](https://doris.apache.org/docs/query-acceleration/materialized-view/sync-materialized-view), [Async MV](https://doris.apache.org/docs/query-acceleration/materialized-view/async-materialized-view), [Inverted Index](https://doris.apache.org/docs/table-design/index/inverted-index), [BloomFilter](https://doris.apache.org/docs/table-design/index/bloomfilter), [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)

## Materialized Views

### Decision: Sync vs Async MV

| Condition | Recommendation | Source |
|-----------|---------------|--------|
| Single-table aggregation on DUP/AGG table | Sync MV | official |
| Multi-table JOIN acceleration | Async MV | official |
| Must be fresh < 1 hour, base table updates ≤5/hr | Async MV with ON COMMIT | official |
| Complex transform, freshness > 1 hour OK | Async MV with SCHEDULE | official |
| UNIQUE KEY table needs aggregation | Async MV (sync MV not supported) | official |
| Layer-to-layer ETL (ODS→DWD→DWS→ADS) | Async MV with partition_sync_limit | official |

### Capacity Planning
- ~20-30 active async MVs on a 3-node cluster (16 vCore, 128GB RAM)
- Each MV costs ~10-15GB storage + refresh compute
- Max 3 concurrent refresh tasks
- Max 30 partitions per MV, max ~50M rows per MV
- Resource ceiling: 40% of cluster for all MV refresh + 20% buffer
- Use `partition_sync_limit` to refresh only recent partitions

## Indexes

### When to Use Which Index

| Condition | Index type | Source |
|-----------|-----------|--------|
| Full-text search on text columns | Inverted Index (unicode/english/chinese parser) | official |
| Equality/range filter on non-key column | Inverted Index (no parser) | official |
| High-cardinality equality filter (≥5000 distinct, `=` or `IN`) | BloomFilter | official |
| LIKE '%pattern%' substring search | NGram BloomFilter | official |
| Medium-cardinality dimension (100-100K distinct) | Bitmap Index | official |
| ANN vector search (<100M vectors, online) | HNSW | official |
| ANN vector search (>100M vectors, batch) | IVF_FLAT or IVF_PQ | official |

### Key Constraints
- BloomFilter: not supported on TINYINT, FLOAT, DOUBLE. Only accelerates `=` and `IN`.
- Bitmap: sweet spot 100-100K distinct values. Below 100 wastes space; above 100K degrades.
- Vector HNSW memory: ~650MB per 1M vectors at 128-dim.
- CDP/funnel analysis: use `bitmap_union()` for union, `bitmap_intersect()` for retention.

## Point Query Optimization

| Technique | Effect | Source |
|-----------|--------|--------|
| `store_row_column = "true"` | Row-store mode, single I/O per row | official |
| PreparedStatement | Reuse query plan, reduce parse overhead | official |
| BloomFilter on lookup key | Skip tablets without the key | official |
| Row cache | Cache individual rows for repeated lookups | derived |

See `decision-mutable-state.md` for the 4-prerequisite SHORT-CIRCUIT checklist.

## Caching

| Cache type | Use when | Source |
|-----------|----------|--------|
| SQL cache | Repeated identical queries (dashboard auto-refresh) | official |
| Partition cache | Time-series with mostly historical data | official |
| File cache (cloud) | Decoupled mode — 60% cached = 95% hit rate | derived |
| Row cache | Point queries on MoW tables | derived |

## Colocation Join

For zero-shuffle JOINs, all 4 conditions must match:
1. Same `colocate_with` group name
2. Same bucket key column(s) and types
3. Same bucket count
4. Same replication_num

For DDL implementation of these decisions, delegate to `doris-best-practices` rules: `schema-mv-sync-rollup`, `schema-mv-async-join`, `schema-mv-async-limits`, `schema-index-inverted`, `schema-index-bloomfilter`, `schema-index-bitmap`, `schema-index-vector`, `usecase-point-query`, `usecase-star-schema-join`.
