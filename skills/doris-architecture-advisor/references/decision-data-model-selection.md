# Data Model Selection

The data model is immutable after table creation. Choose carefully.

## Performance Ranking

Query speed: **DUPLICATE > UNIQUE MoW > UNIQUE MoR ≈ AGGREGATE**

- DUPLICATE: no merge overhead at query time — fastest full scans
- UNIQUE MoW: pre-merged at write time — fast reads, slightly slower writes
- UNIQUE MoR: merge-sort at query time — 2-10x slower reads
- AGGREGATE: similar to MoR for scan queries

Reference: [Data Model Overview](https://doris.apache.org/docs/table-design/data-model/overview)

## Decision Framework

| Condition | Model | Source |
|-----------|-------|--------|
| Append-only data (logs, events, clicks, sensor readings) | DUPLICATE | official |
| Rows are updated or deleted (CDC, user profiles, device state) | UNIQUE MoW | official |
| Pre-aggregated metrics only (counters, sums, never query raw rows) | AGGREGATE | official |
| Need partial column updates | UNIQUE MoW with `enable_unique_key_partial_update` | official |
| Need partial column updates on AGG table | AGGREGATE with REPLACE_IF_NOT_NULL | official |
| Small dimension/lookup table (<1GB, rarely updated) | DUPLICATE with RANDOM bucketing | derived |
| Small dimension table that receives updates | UNIQUE MoW | derived |
| High-write, low-read workload (rare) | UNIQUE MoR (accept read penalty for write speed) | field |

Reference: [Unique Key Model](https://doris.apache.org/docs/table-design/data-model/unique), [Aggregate Model](https://doris.apache.org/docs/table-design/data-model/aggregate)

## Critical Constraints

- **AGGREGATE model cannot UPDATE or DELETE.** No CDC compatibility. No `DELETE FROM`.
- **UNIQUE MoW is default since Doris 2.1.** Always set explicitly for clarity.
- **MoR blocks tiered storage** in some configurations. Prefer MoW unless write throughput is the sole concern.
- **AGG model hides values from ZoneMap** — value columns cannot benefit from min/max pruning.

## VARIANT Type for Semi-structured Data

When device protocols vary or JSON schemas evolve, recommend VARIANT instead of JSON or STRING.

Reference: [VARIANT Type](https://doris.apache.org/docs/sql-manual/data-types/semi-structured/VARIANT)

**When to use VARIANT:**
- Multi-protocol IoT (15+ device types, different schemas)
- User event properties (variable JSON payloads)
- Any semi-structured data where schema changes with firmware/app updates
- 8x faster queries than JSON type, 65% less storage

**When NOT to use VARIANT:**
- All fields are known and stable — use typed columns (better ZoneMap pruning)
- Field is a sort key or partition key — must be a typed column

## Complex Type Limitations

JSON, ARRAY, MAP, STRUCT, VARIANT, BITMAP, HLL columns:
- **No ZoneMap** — cannot prune data pages by min/max
- **No BloomFilter** — cannot skip pages by value lookup
- Always cause full column scan when filtered

**Workaround:** Extract frequently-filtered fields into typed columns. Keep complex types for projection only.

For DDL implementation of these decisions, delegate to `doris-best-practices` rules: `schema-model-choose-for-workload`, `schema-model-prefer-mow`, `schema-types-variant-json`.
