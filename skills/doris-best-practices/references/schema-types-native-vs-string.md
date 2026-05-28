---
title: Use Native Types, Not STRING for Everything
impact: HIGH
impactDescription: "STRING disables ZoneMap, prefix index, and prevents use as key/bucket column"
tags: [schema, types, string, native, performance]
---
## Use Native Types, Not STRING for Everything
**Impact: HIGH — STRING columns cannot be used as partition, bucket, or sort key columns.**
Always use the most specific type: INT for numbers, DATE/DATETIME for timestamps, DECIMAL for money.
```sql
-- BAD
CREATE TABLE t (id STRING, ts STRING, amount STRING);
-- GOOD
CREATE TABLE t (id BIGINT, ts DATETIME(3), amount DECIMAL(12,2));
```
Reference: [Data Types](https://doris.apache.org/docs/sql-manual/data-types/overview)
