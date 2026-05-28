---
title: HNSW/IVF Vector Index for ANN Search (Doris 4.0+)
impact: HIGH
tags: [schema, index, vector, hnsw, ivf, ann, embedding]
---
## HNSW/IVF Vector Index for ANN Search
**Impact: HIGH — Enables approximate nearest neighbor search on embeddings.**
Requires Doris 4.0+ with vector support.
```sql
CREATE TABLE embeddings (
    doc_id BIGINT NOT NULL,
    content VARCHAR(65533),
    embedding ARRAY<FLOAT> NOT NULL
) DUPLICATE KEY(doc_id)
DISTRIBUTED BY HASH(doc_id) BUCKETS 5;  -- calculate: data_per_partition_GB × compression / 2
-- Add HNSW index:
CREATE INDEX idx_vec ON embeddings(embedding) USING HNSW
PROPERTIES("dim" = "768", "metric" = "cosine", "m" = "16", "ef_construction" = "200");
-- Query:
SELECT doc_id, l2_distance(embedding, [0.1, 0.2, ...]) AS dist
FROM embeddings ORDER BY dist LIMIT 10;
```
**Index types:** HNSW (fast, memory-heavy), IVF_FLAT (balanced), IVF_PQ (compressed).
