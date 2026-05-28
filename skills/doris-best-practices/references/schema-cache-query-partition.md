---
title: Query Cache and Partition Cache
impact: MEDIUM
tags: [schema, cache, query-cache, partition-cache]
---
## Query Cache and Partition Cache
**Query cache:** Identical SQL → instant response (no computation).
```sql
SET enable_query_cache = true;
```
**Partition cache:** Only recomputes partitions with new data. Ideal for time-series dashboards where most partitions are historical and unchanged.
```sql
SET enable_partition_cache = true;
```
**When to use:**
- Query cache: Repeated identical queries (dashboard auto-refresh)
- Partition cache: Time-series with mostly historical data
