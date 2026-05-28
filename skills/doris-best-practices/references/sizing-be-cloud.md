---
title: BE Sizing — Cloud / Storage-Compute Separation
tags: [sizing, be, cloud, storage-compute]
---
## BE Sizing — Cloud / Storage-Compute Separation
In cloud mode, data is in object storage (S3/GCS). BEs only cache hot data locally.
**CPU:** Same as integrated — determines query parallelism.
**Memory:** 32-128 GB. Used for query execution, not data storage.
**Local disk:** SSD for file cache. Size based on hot data ratio (60% cached = 95% hit rate).
**Elasticity:** Can scale BE nodes independently from data volume. Add BEs for more compute, not more storage.
