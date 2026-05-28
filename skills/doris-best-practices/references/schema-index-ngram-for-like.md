---
title: NGram BloomFilter for LIKE Queries
impact: HIGH
tags: [schema, index, ngram, like, pattern]
---
## NGram BloomFilter for LIKE '%pattern%' Queries
**Impact: HIGH — LIKE '%pattern%' causes full table scan without NGram index.**
```sql
INDEX idx_url(url) USING NGRAM_BF PROPERTIES("gram_size" = "3", "bf_size" = "1024")
```
The NGram BloomFilter breaks text into 3-character grams and uses a bloom filter to skip non-matching pages.
**When to use:** `LIKE '%keyword%'` queries on VARCHAR/STRING columns.
**When NOT to use:** Exact match (`=`) → use regular BloomFilter. Full-text search → use Inverted Index.
Reference: [NGram BloomFilter](https://doris.apache.org/docs/table-design/index/ngram-bloomfilter-index)
