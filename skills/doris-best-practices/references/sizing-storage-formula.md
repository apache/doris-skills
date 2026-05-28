---
title: Storage Calculation Formula
tags: [sizing, storage, formula, compression]
---
## Storage Calculation Formula
```
Raw data × compression ratio × replication_num = Required storage
```
**Compression ratios (typical):**
| Data Type | LZ4 Ratio | ZSTD Ratio |
|-----------|-----------|------------|
| Structured (numeric) | 3-5× | 5-8× |
| Logs/text | 5-10× | 10-20× |
| JSON/semi-structured | 3-8× | 5-12× |
**Example:** 1 TB/day raw logs × 30 days retention × ZSTD (10× compression) × 1 replica = 3 TB storage
**Include overhead:** Add 20-30% for metadata, compaction temp space, and safety margin.
