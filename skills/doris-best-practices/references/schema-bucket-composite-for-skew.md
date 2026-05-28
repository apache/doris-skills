---
title: Use Composite Bucket Key to Fix Data Skew
impact: HIGH
impactDescription: "Single skewed bucket key concentrates data; composite key distributes it evenly"
tags: [schema, bucket, skew, composite, hotspot]
---

## Use Composite Bucket Key to Fix Data Skew

**Impact: HIGH (Single skewed bucket key concentrates data; composite key distributes it evenly)**

When a single column has uneven distribution (some values appear much more than others), use a composite bucket key.

**Incorrect (single skewed key):**

```sql
-- BAD: site_id 54321 has 80% of traffic → bucket_4 is 80% of data
CREATE TABLE site_access (
    site_id INT, city_code INT, pv BIGINT
) DUPLICATE KEY(site_id, city_code)
DISTRIBUTED BY HASH(site_id) BUCKETS 16;
```

**Correct (composite key):**

```sql
-- GOOD: combining site_id + city_code distributes the hot site across cities
CREATE TABLE site_access (
    site_id INT, city_code INT, pv BIGINT
) DUPLICATE KEY(site_id, city_code)
DISTRIBUTED BY HASH(site_id, city_code) BUCKETS 16;
-- Data for site_id=54321 is now spread across multiple buckets by city.
```

**When to use composite keys:**
- One column dominates traffic (e.g., one large customer)
- Single-column hash creates visible hot tablets
- Detect with: `SHOW TABLETS FROM table_name` and check size distribution

Reference: [Data Distribution](https://doris.apache.org/docs/table-design/data-partitioning/data-distribution)
