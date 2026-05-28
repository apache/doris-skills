---
title: FE Node Sizing
tags: [sizing, fe, frontend, metadata]
---
## FE Node Sizing
| Cluster Size | FE Nodes | Memory | CPU |
|-------------|----------|--------|-----|
| Small (< 10 BE) | 1 Leader + 2 Follower | 16 GB | 8 cores |
| Medium (10-50 BE) | 1 Leader + 2 Follower | 32 GB | 16 cores |
| Large (50+ BE) | 1 Leader + 4 Follower | 64 GB | 32 cores |
FE nodes store metadata (table schemas, partitions, tablets) in memory. Scale FE memory with table count and partition count rather than data volume.
