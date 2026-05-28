---
title: Prefix Index — 36 Bytes, VARCHAR Stops It
impact: CRITICAL
impactDescription: "Only the first 36 bytes of the sort key form the prefix index; VARCHAR terminates it"
tags: [schema, keys, prefix-index, limits, varchar]
---

## Prefix Index — 36 Bytes, VARCHAR Stops It

**Impact: CRITICAL — Columns beyond the limit get no prefix index benefit.**

| Rule | Detail |
|------|--------|
| Max bytes | 36 |
| VARCHAR | **Terminates the index** — only first 20 bytes included, no columns after |
| FLOAT/DOUBLE | **Cannot be in prefix index** — breaks ZoneMap too |

**CRITICAL: Once a VARCHAR column appears, it is the LAST column in the prefix index.** All columns after the first VARCHAR are NEVER indexed, regardless of remaining byte budget.

```sql
-- GOOD: Fixed-length first, VARCHAR last
DUPLICATE KEY(event_time, user_id, country)
-- 8 (DATETIME) + 8 (BIGINT) + up to 20 (VARCHAR, STOPS) = 36B
-- All 3 columns indexed ✓

-- BAD: VARCHAR first — only 1 column indexed
DUPLICATE KEY(session_id, event_time, country)
-- VARCHAR takes up to 20B AND STOPS → event_time, country never indexed ✗

-- GOOD for time-series with string dimensions
DUPLICATE KEY(event_time, country, platform, connection_id)
-- 8B (DATETIME) + country VARCHAR STOPS at 20B
-- event_time + country in prefix index. platform, connection_id are NOT,
-- but they benefit from ZoneMap on sorted data + use inverted indexes.
```

**Design rule:** Place fixed-length columns (DATETIME, INT, BIGINT) before VARCHAR. Put the most useful VARCHAR as the first VARCHAR column — it will be the last indexed column. Use inverted indexes or bloom filters for columns after the first VARCHAR.

Reference: [Prefix Index](https://doris.apache.org/docs/table-design/index/prefix-index)
