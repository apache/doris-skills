---
title: AGGREGATE Model Cannot UPDATE or DELETE
impact: CRITICAL
impactDescription: "Choosing AGG for updatable data is irreversible and blocks CDC pipelines"
tags: [schema, model, aggregate, update, delete]
---

## AGGREGATE Model Cannot UPDATE or DELETE

**Impact: CRITICAL — AGG tables do not support UPDATE or DELETE statements.**

The AGGREGATE model auto-merges rows with the same key using aggregation functions (SUM, MAX, REPLACE, etc). This means:
- No `UPDATE` statement support
- No `DELETE` statement support
- No CDC pipeline compatibility (cannot reflect deletes)

**Exception: REPLACE_IF_NOT_NULL** — The one case where AGG can do partial updates. Columns with `REPLACE_IF_NOT_NULL` will only update when the incoming value is non-NULL. This allows partial column updates in AGG model, but still no DELETE.

**Incorrect:**

```sql
-- BAD: AGG for data that needs updates
CREATE TABLE orders (
    order_id BIGINT AGGREGATE KEY,
    status VARCHAR(20) REPLACE,
    amount DECIMAL(12,2) REPLACE
) AGGREGATE KEY(order_id);
-- Cannot DELETE cancelled orders!
```

**Correct:**

```sql
-- GOOD: UNIQUE MoW for updatable data
CREATE TABLE orders (
    order_id BIGINT NOT NULL,
    status VARCHAR(20),
    amount DECIMAL(12,2)
) UNIQUE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 5  -- calculate: data_per_partition_GB × compression / 2
PROPERTIES ("enable_unique_key_merge_on_write" = "true");
```

Reference: [Aggregate Model](https://doris.apache.org/docs/table-design/data-model/aggregate)
