---
title: "Use Case: Star Schema / JOIN-Heavy Analytics"
impact: CRITICAL
tags: [usecase, star-schema, join, colocation, fact-table, dimension]
---
## Use Case: Star Schema / JOIN-Heavy Analytics
Uses colocation to ensure JOINs execute locally without network shuffle.
### Fact Table
```sql
CREATE TABLE fact_orders (
    order_date DATE NOT NULL, order_id BIGINT NOT NULL,
    user_id INT NOT NULL, store_id INT NOT NULL, product_id INT NOT NULL,
    amount DECIMAL(12,2), quantity INT
) ENGINE=OLAP DUPLICATE KEY(order_date, order_id)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(store_id) BUCKETS 16
PROPERTIES ("dynamic_partition.enable"="true","dynamic_partition.time_unit"="MONTH",
    "dynamic_partition.start"="-24","dynamic_partition.end"="1",
    "dynamic_partition.prefix"="p",
    "colocate_with"="group_orders");
```
### Dimension Table (colocated)
```sql
CREATE TABLE dim_stores (
    store_id INT NOT NULL, region VARCHAR(20), city VARCHAR(50), manager_name VARCHAR(100)
) ENGINE=OLAP DUPLICATE KEY(store_id)
DISTRIBUTED BY HASH(store_id) BUCKETS 16
PROPERTIES ("colocate_with" = "group_orders");
```
### Colocation Rules — ALL must match or CREATE TABLE fails:
1. Same `colocate_with` group name
2. Same bucket key column(s) and same column types
3. **Same bucket count** — if the first table in a group uses BUCKETS 8, ALL other tables in the group MUST also use BUCKETS 8. Mismatched counts cause: `Colocate tables must have same bucket num`
4. Same replication_num

**Common mistake:** Sizing each table's buckets independently, then adding them to the same colocation group. Always decide the bucket count for the group FIRST, then use that count for ALL tables in the group.

### Alternative: Broadcast JOIN + Runtime Filter (for small dims)
When dimension tables are small (<1 GB), **skip colocation** — Doris auto-broadcasts them:
```sql
-- Fact table: HASH on the JOIN key for runtime filter bucket pruning
CREATE TABLE fact_events (
    event_time DATETIME NOT NULL, country VARCHAR(10), conn_id VARCHAR(255),
    adv_spend DECIMAL(12,2), views BIGINT
) DUPLICATE KEY(event_time, country)
AUTO PARTITION BY RANGE(date_trunc(event_time, 'day'))()
DISTRIBUTED BY HASH(conn_id) BUCKETS 8;

-- Small dim: no colocation needed, 1 bucket
CREATE TABLE dim_partners (
    conn_id VARCHAR(255) NOT NULL, partner_name VARCHAR(255), region VARCHAR(50)
) DUPLICATE KEY(conn_id)
DISTRIBUTED BY HASH(conn_id) BUCKETS 1;
```
**How it works:** When a query filters `WHERE dim.partner_name = 'X'`, Doris:
1. Scans the small dim table, applies the filter
2. Generates a **runtime filter** from the matching `conn_id` values
3. Pushes the runtime filter to the fact table scan → **HASH bucket pruning** (scans 1 bucket instead of all)

This gives colocation-like performance without the operational overhead of matching bucket counts across tables. Use colocation only when dims are large (>1 GB) or when both sides of the JOIN are large fact tables.
