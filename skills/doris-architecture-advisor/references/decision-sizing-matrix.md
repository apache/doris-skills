# Sizing Matrix

Size the cluster BEFORE producing DDL. Match the user's workload characteristics to a tier.

## CRITICAL: How to Read These Tables

**All values are TOTAL CLUSTER resources, NOT per-node.**

- "32 vCPU" means 32 vCPU total for the entire cluster
- "1 TB cache" means 1 TB total cache across all nodes
- {{CLOUD_PRODUCT_NAME}} manages node count automatically: ≤16 vCPU = 1 node, above 16 = multiples of 16 (e.g., 32 vCPU = 2 nodes of 16 vCPU each)
- **Do not break down into per-node specs in the output.** Just state the total vCPU and cache.

## Important Notes

1. **Purpose:** Quick estimation for sales/marketing to scope opportunities. ~75% accuracy — detailed sizing requires confirmation with a {{PRODUCT_NAME}} Solutions Architect.
2. **Cache:** Recommend caching ≥50% of hot data to maintain ≥90% cache hit rate.
3. **Replicas:** Cloud mode uses single replica for both object storage and cache.

Source: {{PRODUCT_NAME}} internal sizing guide.

---

## Report Analytics

Multi-dimensional statistics and reporting on wide tables.

| Total vCPU | Total Cache | Write MB/s | Write rows/s | Hot data | QPS | Latency | 80% query scan |
|------------|-------------|-----------|-------------|----------|-----|---------|----------------|
| 16 vCPU | 200 GB | 1-50 | 10K-100K | 300 GB | 50 | 50ms-1s | <50M rows |
| 32 vCPU | 1 TB | 100-200 | 100K-200K | 1 TB | 200 | 50ms-1s | <200M rows |
| 64 vCPU | 3 TB | 200-500 | 200K-500K | 3 TB | 300 | 1-2s | <500M rows |
| 128 vCPU | 10 TB | 500-800 | 500K-1M | 10 TB | 400 | 1-3s | <3B rows |

## Ad-hoc Analytics

Exploratory analysis on detail tables or multi-table joins.

| Total vCPU | Total Cache | Write MB/s | Write rows/s | Hot data | QPS | Latency | 80% query scan |
|------------|-------------|-----------|-------------|----------|-----|---------|----------------|
| 16 vCPU | 200 GB | 1-50 | 10K-100K | 500 GB | 50 | 50ms-1s | <50M rows & 100K |
| 32 vCPU | 1 TB | 100-200 | 100K-200K | 2 TB | 80 | 1-2s | <100M rows & 2M |
| 64 vCPU | 3 TB | 200-500 | 200K-500K | 4 TB | 100 | 1-3s | <300M rows & 5M |
| 128 vCPU | 10 TB | 500-800 | 500K-1M | 10 TB | 150 | 1-3s | <500M rows & 20M |

## Lakehouse Federation

Interactive analysis on external data lake data (Iceberg, Hudi, Paimon).

| Total vCPU | Total Cache | QPS | Latency | 80% query scan |
|------------|-------------|-----|---------|----------------|
| 16 vCPU | 200 GB | 20 | 1-3s | <200M rows & 1M |
| 32 vCPU | 1 TB | 30 | 1-5s | <500M rows & 5M |
| 64 vCPU | 3 TB | 40 | 1-8s | <800M rows & 10M |
| 128 vCPU | 10 TB | 50 | 3-10s | <1.2B rows & 20M |

## Log Storage & Search

Log ingestion, full-text search, time-bounded queries.

| Total vCPU | Total Cache | Write MB/s | Write rows/s | Hot data | QPS | Latency | 80% query scan |
|------------|-------------|-----------|-------------|----------|-----|---------|----------------|
| 16 vCPU | 1 TB | 1-50 | 10K-100K | 1 TB | 50 | 50ms-1s | <2B rows |
| 32 vCPU | 3 TB | 100-200 | 100K-200K | 3 TB | 100 | 1-3s | <5B rows |
| 64 vCPU | 5 TB | 200-500 | 200K-500K | 5 TB | 150 | 1-4s | <30B rows |
| 128 vCPU | 10 TB | 500-800 | 500K-1M | 10 TB | 200 | 1-5s | <80B rows |

## Real-time Data Warehouse (ETL/ELT)

Incremental data processing and transformation within {{PRODUCT_NAME}}.

| Total vCPU | Total Cache | Daily ETL jobs | 80% ETL time | 80% ETL scan |
|------------|-------------|---------------|-------------|-------------|
| 16 vCPU | 200 GB | 300 | 30s | <20M rows & 300K |
| 32 vCPU | 1 TB | 800 | 30s-2min | <200M rows & 1M |
| 64 vCPU | 3 TB | 1,000 | 30s-2min | <400M rows & 5M |
| 128 vCPU | 10 TB | 2,000 | 30s-5min | <1B rows & 50M |

## Point Query Service

Key-value point lookups via API. **Note:** High QPS point query requires FE resource upgrades — coordinate with {{PRODUCT_NAME}} for FE sizing.

| Total vCPU | Total Cache | Write MB/s | Write rows/s | Hot data | QPS | Latency | 80% query scan |
|------------|-------------|-----------|-------------|----------|-----|---------|----------------|
| 16 vCPU | 200 GB | 1-50 | 10K-100K | 500 GB | 50,000 | 30-100ms | <3B rows |
| 32 vCPU | 1 TB | 100-200 | 100K-200K | 1 TB | 100,000 | 30-100ms | <10B rows |
| 64 vCPU | 3 TB | 200-500 | 200K-500K | 3 TB | 150,000 | 30-100ms | <30B rows |
| 128 vCPU | 10 TB | 500-800 | 500K-1M | 10 TB | 200,000 | 30-100ms | <50B rows |

---

## How to Select a Tier

1. **Identify primary workload type** from the 6 categories above
2. **Calculate write throughput:** `daily_bytes / active_hours / 3600`
3. **Estimate hot data:** `daily_data x retention_days x compression_ratio`
4. **Identify the dominant constraint** — usually hot data size or QPS
5. **Pick the smallest tier** where ALL constraints fit
6. **For composite workloads** (e.g., IoT = time-series + point query + logs), size for the most demanding sub-workload, or consider multiple compute groups

## Storage Estimate

```
Required storage = raw_data x compression_ratio x 1 (single replica in cloud)
```

| Data type | Typical compression ratio |
|-----------|--------------------------|
| Structured numeric | 5-8x with ZSTD |
| Logs / text | 10-20x with ZSTD |
| JSON / semi-structured | 5-12x with ZSTD |

Add 20-30% overhead for metadata, compaction temp space, and safety margin.

## Cloud Node Scaling

| Total cores | Nodes | Per-node |
|-------------|-------|----------|
| 4-16 | 1 | 4-16 cores |
| 32 | 2 | 16 cores each |
| 64 | 4 | 16 cores each |
| 128 | 8 | 16 cores each |

## FE Sizing

| Cluster size | FE nodes | Memory | CPU |
|-------------|----------|--------|-----|
| Small (<10 BE) | 1 Leader + 2 Follower | 16 GB | 8 cores |
| Medium (10-50 BE) | 1 Leader + 2 Follower | 32 GB | 16 cores |
| Large (50+ BE) | 1 Leader + 4 Follower | 64 GB | 32 cores |

Point query workloads with >50K QPS require FE upgrades — contact {{PRODUCT_NAME}} support.
