---
title: JSON/ARRAY/Complex Types Disable ZoneMap
impact: HIGH
tags: [schema, types, zonemap, json, array, complex]
---
## JSON/ARRAY/Complex Types Disable ZoneMap
**Impact: HIGH — ZoneMap statistics are not generated for JSON, ARRAY, MAP, STRUCT, or STRING columns.**
ZoneMap stores min/max values per data page, enabling skip scanning. Complex types disable this optimization.
**Workaround:** Extract frequently filtered fields into dedicated columns with native types.
```sql
-- BAD: Filtering on JSON field — no ZoneMap, full scan
SELECT * FROM events WHERE payload->'$.status' = 'error';
-- GOOD: Extract to a native column
CREATE TABLE events (
    ..., status VARCHAR(20), payload JSON,
    INDEX idx_status(status) USING INVERTED
);
SELECT * FROM events WHERE status = 'error';
```
