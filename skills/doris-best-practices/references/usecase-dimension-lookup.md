---
title: "Use Case: Small Dimension / Lookup Table"
impact: HIGH
tags: [usecase, dimension, lookup, small-table, broadcast, random]
---
## Use Case: Small Dimension / Lookup Table
For small reference tables (< 1 GB): products, stores, countries, config values.
### Template
```sql
CREATE TABLE stores (
    store_id INT NOT NULL, region VARCHAR(20) NOT NULL,
    city VARCHAR(50), manager_name VARCHAR(100)
) ENGINE=OLAP DUPLICATE KEY(store_id)
DISTRIBUTED BY RANDOM BUCKETS 3
PROPERTIES ("replication_num" = "3");  -- Use "1" for cloud mode
```
### Why This Design
| Decision | Choice | Why |
|----------|--------|-----|
| **Model** | DUPLICATE | Dimension data is reference data — rarely updated. |
| **Partition** | None | Table is tiny (< 1 GB). Partitioning adds overhead, not benefit. |
| **Bucket** | RANDOM, 3 buckets | Perfectly even distribution for small data. |
### Customization Points
- **Updated dimensions:** Switch to `UNIQUE KEY(store_id)` with MoW if dimension data changes
- **Colocation JOINs:** Switch to `HASH(store_id)` and match the fact table's bucket count
