---
title: DDL Syntax Gotchas — Common Apache Doris CREATE TABLE Mistakes
impact: CRITICAL
tags: [schema, ddl, gotchas, syntax, validation]
---

## DDL Syntax Gotchas

**Check EVERY CREATE TABLE against these constraints before outputting DDL. These are hard errors — Apache Doris will reject the statement.**

### 1. UNIQUE KEY (MoW) + PARTITION BY RANGE: partition column MUST be in key

```sql
-- FAILS:
UNIQUE KEY(trade_id)
PARTITION BY RANGE(trade_time)  -- ERROR: trade_time not in key

-- CORRECT:
UNIQUE KEY(trade_id, trade_time)
PARTITION BY RANGE(trade_time)
```

### 2. Key columns must be the FIRST N columns of the schema, in order

```sql
-- FAILS: key says (log_time, account_id, action) but schema has session_id at position 3
CREATE TABLE t (log_time DATETIME, order_id BIGINT, account_id VARCHAR, session_id VARCHAR, action VARCHAR)
DUPLICATE KEY(log_time, account_id, action)  -- ERROR

-- CORRECT: put key columns first, then everything else
CREATE TABLE t (log_time DATETIME, account_id VARCHAR, action VARCHAR, order_id BIGINT, session_id VARCHAR)
DUPLICATE KEY(log_time, account_id, action)
```

### 3. store_row_column only works on UNIQUE KEY (MoW) — NOT on AGGREGATE or DUPLICATE

```sql
-- FAILS:
AGGREGATE KEY(user_id) PROPERTIES ("store_row_column" = "true")  -- ERROR

-- CORRECT: only on UNIQUE KEY with MoW
UNIQUE KEY(user_id) PROPERTIES ("enable_unique_key_merge_on_write" = "true", "store_row_column" = "true")
```

### 4. AUTO PARTITION requires date_trunc() AND empty parens ()

```sql
-- FAILS:
AUTO PARTITION BY RANGE(event_time)                         -- ERROR: must use date_trunc
AUTO PARTITION BY RANGE(date_trunc(event_time, 'day'))      -- ERROR: missing () at end

-- CORRECT:
AUTO PARTITION BY RANGE(date_trunc(event_time, 'day')) ()   -- note the () before DISTRIBUTED
```

The partition column must also be NOT NULL.

### 5. Dynamic partition properties require explicit PARTITION BY RANGE clause

```sql
-- FAILS: has dynamic_partition properties but no PARTITION BY
CREATE TABLE t (...) DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES ("dynamic_partition.enable" = "true", "dynamic_partition.time_unit" = "DAY")  -- ERROR

-- CORRECT: add PARTITION BY RANGE(col) ()
CREATE TABLE t (...) PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 5
PROPERTIES ("dynamic_partition.enable" = "true", "dynamic_partition.time_unit" = "DAY")
```

### 6. compaction_policy = "time_series" only for DUPLICATE tables

```sql
-- FAILS:
UNIQUE KEY(id) PROPERTIES ("compaction_policy" = "time_series")  -- ERROR on UNIQUE

-- CORRECT: only on DUPLICATE
DUPLICATE KEY(ts, id) PROPERTIES ("compaction_policy" = "time_series")
```

### 7. Async MV refresh syntax: must include method and ON SCHEDULE

```sql
-- FAILS:
REFRESH SCHEDULE EVERY 10 MINUTES   -- wrong
REFRESH ASYNC EVERY(INTERVAL 1 DAY) -- wrong

-- CORRECT:
REFRESH AUTO ON SCHEDULE EVERY 10 MINUTE  -- method + ON SCHEDULE; MINUTE not MINUTES
```

### 8. Async MV minimum refresh interval is 1 MINUTE

```sql
-- FAILS:
REFRESH ON SCHEDULE EVERY 30 SECOND  -- ERROR: SECOND not supported

-- CORRECT:
REFRESH ON SCHEDULE EVERY 1 MINUTE
```

### 9. Async MV using NOW() requires nondeterministic flag

```sql
-- FAILS:
CREATE MATERIALIZED VIEW mv AS SELECT ... WHERE ts > NOW() - INTERVAL 7 DAY  -- ERROR

-- CORRECT: add property
CREATE MATERIALIZED VIEW mv
PROPERTIES ("enable_nondeterministic_function" = "true")
REFRESH ON SCHEDULE EVERY 10 MINUTE
AS SELECT ... WHERE ts > NOW() - INTERVAL 7 DAY
```

### 10. enable_unique_key_partial_update is a SESSION variable, not a table property

```sql
-- FAILS:
PROPERTIES ("enable_unique_key_partial_update" = "true")  -- not a valid table property

-- CORRECT: set at write time
SET enable_unique_key_partial_update = true;
INSERT INTO table (key_col, partial_col) VALUES (...);
```

### 11. BOOLEAN default syntax

```sql
-- FAILS:
is_active BOOLEAN DEFAULT TRUE   -- ERROR
is_active BOOLEAN DEFAULT "null" -- ERROR

-- CORRECT:
is_active BOOLEAN DEFAULT "true"
is_active BOOLEAN DEFAULT "false"
```

### 12. AGGREGATE columns: DEFAULT "null" is invalid on non-string types

In AGGREGATE tables, `REPLACE_IF_NOT_NULL DEFAULT "null"` works for VARCHAR but fails for INT, DATE, DECIMAL, BIGINT, etc. because `"null"` is not a valid number/date.

```sql
-- FAILS:
vip_level INT REPLACE_IF_NOT_NULL DEFAULT "null"      -- ERROR: Invalid number format: null
last_login DATE REPLACE_IF_NOT_NULL DEFAULT "null"     -- ERROR: Invalid date format

-- CORRECT: omit DEFAULT entirely — NULL is already the default for REPLACE_IF_NOT_NULL
vip_level INT REPLACE_IF_NOT_NULL
last_login DATE REPLACE_IF_NOT_NULL

-- Also CORRECT for VARCHAR (string can hold "null" literal, but prefer omitting):
gender VARCHAR(10) REPLACE_IF_NOT_NULL
```

Reference: [Apache Doris DDL](https://doris.apache.org/docs/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE)
