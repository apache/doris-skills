---
title: Properties Cloud Mode Forces
impact: HIGH
tags: [schema, properties, cloud, replication]
---
## Properties Cloud Mode Forces
In Cloud mode (storage-compute separation):
- `replication_num` is forced to `1` (data stored in object storage)
- HASH bucketing required for UNIQUE MoW
- File cache controls performance (see `schema-cache-file-cache`)
```sql
PROPERTIES ("replication_num" = "1");
```
