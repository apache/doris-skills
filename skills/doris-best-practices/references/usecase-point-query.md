---
title: "Use Case: User-Facing Point Query Analytics"
impact: CRITICAL
tags: [usecase, point-query, user-facing, low-latency, api, high-concurrency]
---
## Use Case: User-Facing Point Query Analytics
For serving real-time analytics through APIs with low-latency, high-concurrency requirements.
### Template
```sql
CREATE TABLE user_profiles (
    user_id BIGINT NOT NULL, tenant_id INT NOT NULL,
    name VARCHAR(100), email VARCHAR(200), last_login DATETIME,
    total_orders INT, lifetime_value DECIMAL(12,2)
) ENGINE=OLAP UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5  -- user profiles: calculate: data_per_partition_GB × compression / 2
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "store_row_column" = "true",
    "light_schema_change" = "true",
    "bloom_filter_columns" = "tenant_id"
);
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | UNIQUE MoW | Fast reads (no merge-sort at query time) |
| **store_row_column** | `true` | Enables row-store mode for point queries — reads full row from one I/O |
| **BloomFilter** | On `tenant_id` | Skips tablets that don't contain the tenant |
### Optimized Point Query Pattern
```sql
SELECT * FROM user_profiles WHERE user_id = 12345;
-- With Prepared Statement for high concurrency:
PREPARE stmt FROM 'SELECT * FROM user_profiles WHERE user_id = ?';
SET @uid = 12345; EXECUTE stmt USING @uid;
```
