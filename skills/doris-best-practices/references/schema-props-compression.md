---
title: LZ4 Default vs ZSTD for Logs/Cold Data
impact: MEDIUM
tags: [schema, properties, compression, lz4, zstd]
---
## LZ4 Default vs ZSTD for Logs/Cold Data
| Algorithm | Speed | Ratio | Use When |
|-----------|-------|-------|----------|
| LZ4 | Fastest | Lower | Default, hot data, low-latency |
| ZSTD | Slower | 2-3× better | Logs, cold data, archival |
```sql
-- For log/event tables with high redundancy:
PROPERTIES ("compression" = "zstd");
-- For hot analytical tables (default):
PROPERTIES ("compression" = "lz4");
```
