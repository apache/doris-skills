---
title: Avoid FLOAT/DOUBLE in Sort Key
impact: HIGH
impactDescription: "FLOAT/DOUBLE break both prefix index and ZoneMap statistics"
tags: [schema, keys, float, double, zonemap]
---

## Avoid FLOAT/DOUBLE in Sort Key

**Impact: HIGH — FLOAT/DOUBLE columns disable prefix index and ZoneMap pruning.**

- FLOAT and DOUBLE **cannot participate** in the prefix index
- They also **disable ZoneMap** statistics for that column
- Use DECIMAL instead for numeric precision

```sql
-- BAD: FLOAT in key breaks prefix index
DUPLICATE KEY(price, product_id)  -- price is FLOAT

-- GOOD: Use DECIMAL
CREATE TABLE products (
    product_id INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    name VARCHAR(200)
) DUPLICATE KEY(product_id, price);
```

Reference: [Prefix Index](https://doris.apache.org/docs/table-design/index/prefix-index)
