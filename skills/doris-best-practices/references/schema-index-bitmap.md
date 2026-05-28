---
title: Bitmap Index for Medium-Cardinality Dimensions
impact: MEDIUM
tags: [schema, index, bitmap, cardinality, dimension]
---
## Bitmap Index for Medium-Cardinality Dimensions (100-100K distinct values)
**Impact: MEDIUM — Efficient for columns with moderate cardinality used in filters.**
```sql
CREATE INDEX idx_city ON table_name(city) USING BITMAP;
```
**Sweet spot:** 100 to 100,000 distinct values (status codes, cities, categories).
**Restrictions:**
- Only one bitmap index can be created at a time (sequential schema change)
- `DROP INDEX` is also a schema change and takes significant time
- Only on value columns, not key columns
- Segment V2 format required
