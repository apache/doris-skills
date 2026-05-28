---
title: VARIANT Type for Semi-Structured JSON Data
impact: HIGH
tags: [schema, types, variant, json, semi-structured, schema-template]
---
## VARIANT Type for Semi-Structured JSON Data
**Impact: HIGH — VARIANT provides columnar storage for JSON with automatic type inference.**
Use VARIANT instead of JSON or STRING for semi-structured data:
```sql
CREATE TABLE events (
    event_time DATETIME NOT NULL,
    event_id BIGINT NOT NULL,
    data VARIANT
) DUPLICATE KEY(event_time, event_id)
DISTRIBUTED BY HASH(event_id) BUCKETS 5;  -- calculate: data_per_partition_GB × compression / 2
-- Query nested fields directly:
SELECT data['user']['name'], data['action'] FROM events;
```
**Schema Template:** Pre-define expected fields for better columnar storage:
```sql
ALTER TABLE events SET ("variant_schema_template" = '{"user.name": "STRING", "action": "STRING", "amount": "DOUBLE"}');
```
**Inverted Index on VARIANT fields:**
```sql
ALTER TABLE events ADD INDEX idx_action(CAST(data['action'] AS VARCHAR)) USING INVERTED;
```
**MATCH search on VARIANT text fields:**
```sql
SELECT * FROM events WHERE CAST(data['message'] AS VARCHAR) MATCH 'error timeout';
```
Reference: [VARIANT Type](https://doris.apache.org/docs/sql-manual/data-types/semi-structured/VARIANT)
