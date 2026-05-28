---
title: Doris-Specific Type Gotchas
impact: HIGH
tags: [schema, types, datetime, string, varchar, char]
---
## Doris-Specific Type Gotchas
**DATETIME precision:** Default DATETIME is seconds. Use `DATETIME(3)` for milliseconds, `DATETIME(6)` for microseconds.
**STRING vs VARCHAR:** STRING cannot be used as key, partition, or bucket column. Use VARCHAR for keyed columns.
**VARCHAR(65533) has identical performance to VARCHAR(255)** — Doris uses variable-length storage, so there's no penalty for a larger max. When unsure, use VARCHAR(65533).
**CHAR vs VARCHAR:** CHAR pads with spaces to fixed length. Only use CHAR for truly fixed-width codes (country_code CHAR(3)). Otherwise, prefer VARCHAR.
```sql
-- GOOD: Appropriate types
CREATE TABLE t (
    ts DATETIME(3),           -- millisecond precision
    country CHAR(3),          -- fixed 3-char code
    name VARCHAR(65533),      -- variable, no perf penalty
    big_text STRING            -- only for non-key, non-partitioned columns
);
```
