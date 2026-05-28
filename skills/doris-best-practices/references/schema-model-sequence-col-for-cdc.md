---
title: Sequence Column for Out-of-Order CDC
impact: HIGH
impactDescription: "Without sequence_col, late-arriving CDC events can overwrite newer data"
tags: [schema, model, cdc, sequence, unique]
---

## Sequence Column for Out-of-Order CDC

**Impact: HIGH — CDC events may arrive out of order; older records can overwrite newer ones.**

When using UNIQUE KEY with CDC (Flink CDC, Debezium, Canal), set a sequence column to guarantee ordering:

```sql
CREATE TABLE users (
    user_id BIGINT NOT NULL,
    update_time DATETIME NOT NULL,
    name VARCHAR(100),
    email VARCHAR(200)
) UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- CDC table: calculate: data_per_partition_GB × compression / 2
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time"
);
```

**How it works:** When two rows have the same primary key, Doris keeps the one with the *higher* sequence column value, regardless of arrival order.

**When to use:** Any CDC pipeline where events may arrive out of order (network delays, reprocessing, multiple sources).

Reference: [Sequence Column](https://doris.apache.org/docs/table-design/data-model/unique#sequence-column)
