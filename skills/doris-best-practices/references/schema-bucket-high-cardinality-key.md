---
title: Choose High-Cardinality, Low-NULL Bucket Key
impact: HIGH
impactDescription: "Low-cardinality bucket key causes data skew and hot tablets"
tags: [schema, bucket, cardinality, skew]
---

## Choose High-Cardinality, Low-NULL Bucket Key

**Impact: HIGH — Low-cardinality keys cause uneven data distribution.**

Good bucket key properties:
1. **High cardinality** — many distinct values (user_id, order_id)
2. **Low NULL rate** — NULLs all hash to the same bucket
3. **Used in WHERE/JOIN** — enables partition pruning

**Bad choices:** status (3 values), gender (2 values), country (200 values for global data)
**Good choices:** user_id, order_id, device_id, session_id

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)
