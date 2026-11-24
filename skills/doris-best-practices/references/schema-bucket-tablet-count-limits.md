---
title: Control Tablet Count — Metadata Scale and Write-Throughput Limits
impact: HIGH
impactDescription: "Excess tablets exhaust FE metadata memory and fragment writes into many small files"
tags: [schema, bucket, tablet, metadata, limits, write-throughput]
---

## Control Tablet Count — Metadata Scale and Write-Throughput Limits

**Impact: HIGH — Too many tablets both exhaust FE metadata memory and fragment writes into many small files.**

### Metadata scale (FE / BE)

- **FE:** every 10 million tablets require roughly 100 GB of FE memory.
- **BE:** a single BE should hold fewer than 20,000 tablets.

### Write throughput

- **Buckets per partition:** keep below 128 — more buckets significantly degrade write performance.
- **Concentrate each write** on a small number of partitions to avoid scattered writes producing many small files.

### Related rules

- Partition column → time or low-cardinality enum: `schema-partition-*`
- Bucket column → high cardinality (e.g. `user_id`): `schema-bucket-high-cardinality-key`
- Single tablet size → 1–10 GB: `schema-bucket-target-size`

Reference: [Basic Concepts](https://doris.apache.org/docs/table-design/data-partitioning/basic-concepts)
