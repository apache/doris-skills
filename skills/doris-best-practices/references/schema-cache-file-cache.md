---
title: File Cache Strategies for Cloud Mode
impact: MEDIUM
tags: [schema, cache, file-cache, cloud, storage-compute]
---
## File Cache Strategies (Cloud / Storage-Compute Separation)
**Key metric: 60% of data cached locally = 95% cache hit rate.** Maintain 90%+ hit rate.
Cache modes:
- **LRU (default):** Evicts least recently used. Good for uniform access.
- **TTL:** Time-based eviction. Good for time-series with clear hot/cold boundary.
**Table-level cache control:**
```sql
-- Keep dimension tables cached forever
ALTER TABLE dim_stores SET ("file_cache_ttl_seconds" = "0");  -- 0 = never evict
-- Hot window for fact tables
ALTER TABLE fact_orders SET ("file_cache_ttl_seconds" = "604800");  -- 7 days
```
**IOPS guidance:** SSD cache: ~500 IOPS/disk. HDD: ~200 IOPS/disk.
