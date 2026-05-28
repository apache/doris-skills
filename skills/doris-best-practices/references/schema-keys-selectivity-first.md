---
title: High-Selectivity Columns First in Sort Key
impact: CRITICAL
impactDescription: "Sort key order determines prefix index effectiveness and ZoneMap pruning"
tags: [schema, keys, sort, selectivity, prefix-index]
---

## High-Selectivity Columns First in Sort Key

**Impact: CRITICAL — Sort key order determines query performance through prefix index.**

Place columns in this order:
1. Most frequently filtered columns first
2. Higher selectivity (more distinct values) before lower
3. Equality filters before range filters

```sql
-- GOOD: user_id (high selectivity, common filter) first
DUPLICATE KEY(user_id, event_time, event_type)

-- BAD: event_type (low selectivity) first
DUPLICATE KEY(event_type, event_time, user_id)
```

The first 3 columns (or first 36 bytes) form the **prefix index**, which is the primary lookup structure in Doris.

**CRITICAL CONSTRAINT: Key columns must be the FIRST N columns of the schema, in the SAME order.**

This is a hard Doris constraint — DDL will fail if violated. When writing CREATE TABLE:
1. Decide which columns go in the key
2. Put those columns FIRST in the column list, in the same order as the key
3. Put all non-key columns AFTER the key columns

```sql
-- BAD: key says (log_time, account_id, action) but schema has session_id between account_id and action
CREATE TABLE t (
    log_time DATETIME,     -- key col 1 ✓
    order_id BIGINT,       -- NOT a key col, but appears before key col 2 ✗
    account_id VARCHAR(32),-- key col 2, but at schema position 3 ✗
    session_id VARCHAR(32),-- NOT a key col, but appears before key col 3 ✗
    action VARCHAR(50)     -- key col 3, but at schema position 5 ✗
) DUPLICATE KEY(log_time, account_id, action)  -- ERROR

-- GOOD: key columns first, then everything else
CREATE TABLE t (
    log_time DATETIME,     -- key col 1 ✓
    account_id VARCHAR(32),-- key col 2 ✓
    action VARCHAR(50),    -- key col 3 ✓
    order_id BIGINT,       -- non-key, after all key cols ✓
    session_id VARCHAR(32) -- non-key, after all key cols ✓
) DUPLICATE KEY(log_time, account_id, action)  -- OK
```

Reference: [Sort Key](https://doris.apache.org/docs/table-design/index/prefix-index)
