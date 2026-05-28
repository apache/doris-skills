---
title: Fixed-Length Types Before VARCHAR in Key
impact: HIGH
impactDescription: "VARCHAR in sort key terminates the prefix index early"
tags: [schema, keys, sort, varchar, fixed-length]
---

## Fixed-Length Types (INT/DATE) Before VARCHAR in Key

**Impact: HIGH — A VARCHAR column terminates the prefix index.**

Prefix index rules:
- Max 3 columns OR 36 bytes (whichever comes first)
- **VARCHAR terminates the index** — only the first 20 bytes of the VARCHAR are included, and no more columns after it

```sql
-- GOOD: Fixed-length types first
DUPLICATE KEY(user_id, event_date, event_type)
--            INT(4B)  DATE(4B)    VARCHAR(→ terminates)

-- BAD: VARCHAR first wastes the prefix index
DUPLICATE KEY(event_type, user_id, event_date)
--            VARCHAR(→ terminates after 20B, user_id and event_date NOT in index)
```

Reference: [Prefix Index](https://doris.apache.org/docs/table-design/index/prefix-index)
