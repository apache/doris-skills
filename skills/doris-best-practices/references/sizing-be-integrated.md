---
title: BE Sizing — Integrated Storage Mode
tags: [sizing, be, backend, integrated]
---
## BE Sizing — Integrated Storage Mode
In integrated mode, each BE stores data locally on disk.
**CPU:** 16-64 cores per BE. More cores = more concurrent query/scan threads.
**Memory:** 64-256 GB per BE. Rule of thumb: 4 GB RAM per 1 TB stored data.
**Disk:** SSD recommended. 1-10 TB per BE. Use RAID or multiple disks for throughput.
**Node count:** Start with 3 nodes for HA. Scale horizontally for more throughput.
