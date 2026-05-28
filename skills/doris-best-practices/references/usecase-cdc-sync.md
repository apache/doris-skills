---
title: "Use Case: CDC / Operational Data Sync"
impact: CRITICAL
tags: [usecase, cdc, sync, mysql, flink, unique, mow, upsert]
---
## Use Case: CDC / Operational Data Sync
For replicating operational databases (MySQL, PostgreSQL) where rows are frequently updated or deleted.
### Template
```sql
CREATE TABLE users_sync (
    user_id BIGINT NOT NULL,
    tenant_id INT NOT NULL,
    update_time DATETIME NOT NULL,
    name VARCHAR(100),
    email VARCHAR(200),
    status TINYINT
) ENGINE=OLAP
UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- CDC table: calculate: data_per_partition_GB × compression / 2
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "light_schema_change" = "true"
);
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | UNIQUE (MoW) | Enables UPDATE/DELETE. MoW gives fast reads without merge-sort. |
| **Sequence col** | `update_time` | Guarantees out-of-order CDC events don't overwrite newer data. |
| **Bucket** | HASH on `user_id` (= primary key) | Point lookups on PK are pruned to one tablet. |
| **Partition** | None | CDC tables are often small-to-medium; partition only if > 100GB. |
### Customization Points
- **Large CDC tables (> 100GB):** Add `PARTITION BY RANGE(update_time) ()` with dynamic partition. **CRITICAL:** The partition column must be in the UNIQUE KEY — change to `UNIQUE KEY(user_id, update_time)`
- **Composite primary key:** Use `UNIQUE KEY(tenant_id, user_id)` for multi-tenant data
- **Partial column updates:** Do NOT set `enable_unique_key_partial_update` as a table property — it is a session variable. Set it at write time: `SET enable_unique_key_partial_update = true;` before your INSERT/Stream Load.
