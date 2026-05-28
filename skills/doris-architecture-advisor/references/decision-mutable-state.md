# Mutable State & CDC Handling

For workloads where rows are updated or deleted: CDC sync, device shadow, user profiles.

Reference: [Unique Key Model](https://doris.apache.org/docs/table-design/data-model/unique), [Sequence Column](https://doris.apache.org/docs/table-design/data-model/unique#sequence-column)

## Decision Framework

| Condition | Recommendation | Source |
|-----------|---------------|--------|
| Replicate MySQL/PostgreSQL via CDC (Flink CDC, Debezium) | UNIQUE MoW + sequence_col | official |
| Device shadow / digital twin (latest device state) | UNIQUE MoW + sequence_col on event timestamp | derived |
| Out-of-order events from IoT sensors or distributed producers | sequence_col guarantees newest wins | official |
| Need partial column updates (update only some fields) | UNIQUE MoW + `enable_unique_key_partial_update` | official |
| Need partial updates on AGG model | REPLACE_IF_NOT_NULL aggregation (lighter than MoW) | official |
| Immutable event log with latest-state queries | Append-only DUPLICATE + async MV for latest state | derived |

## Sequence Column for Out-of-Order Data

IoT data arrives out of order due to: sensor faults, network delays, clock sync drift. Without sequence_col, a delayed old event can overwrite a newer one.

**How it works:** When two rows have the same primary key, Doris keeps the one with the higher sequence_col value, regardless of arrival order.

## SHORT-CIRCUIT Point Query Optimization

For high-concurrency point queries on UNIQUE MoW tables, all 4 prerequisites must be met:

1. `enable_unique_key_merge_on_write = "true"` (MoW enabled)
2. `store_row_column = "true"` (row-store mode)
3. `light_schema_change = "true"` (default since 2.0)
4. WHERE clause uses only key columns

**Performance:** 16-core single node can achieve 30K QPS, avg 7ms, P99 17ms.

Reference: [Prefix Index / Cluster Key](https://doris.apache.org/docs/table-design/index/prefix-index#cluster-key)

## Cluster Key for UNIQUE Tables

When queries filter on columns different from the primary key, use cluster_key to decouple sort order from dedup key. Dedup by primary key, but data sorted by cluster_key columns (faster for filtered queries).

## Cloud Mode Considerations

In Cloud mode (decoupled storage), UNIQUE MoW tables have additional overhead:
- Delete bitmap synced via RPC (slight write latency)
- HASH bucketing required (RANDOM not supported for MoW in cloud)
- For snapshot-consistent point queries: `enable_snapshot_point_query = false` can skip version sync RPC

For DDL implementation of these decisions, delegate to `doris-best-practices` rules: `schema-model-prefer-mow`, `schema-model-sequence-col-for-cdc`, `schema-keys-cluster-key-for-mow`, `usecase-cdc-sync`, `usecase-point-query`.
