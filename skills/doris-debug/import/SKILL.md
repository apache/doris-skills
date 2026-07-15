---
name: doris-debug-import
description: >
  Use for Doris Stream/Broker/Routine Load issues and Group Commit async_mode WAL
  pile-up. Tunables: table group_commit_interval_ms / group_commit_data_bytes;
  BE group_commit_insert_threads, group_commit_wal_path, group_commit_wal_max_disk_limit.
version: 0.1.0
category: import
---

# Import / Group Commit

## async_mode WAL semantics

Write WAL → RPC returns → background group commit → **delete_wal** on success  
(`group_commit_mgr.cpp`). Drain rate = commit finish rate ≠ compaction GB/s.

## Knobs (config.cpp)

| Config | Default | Role |
|--------|---------|------|
| `group_commit_insert_threads` | 10 | commit worker pool |
| `group_commit_relay_wal_threads` | 10 | WAL replay |
| `group_commit_wal_path` | under storage_root | WAL disks |
| `group_commit_wal_max_disk_limit` | 10% | WAL quota |
| table `group_commit_data_bytes` | often 64MB | size flush |
| table `group_commit_interval_ms` | often 10000 | time flush |

## High MB/s guidance

1. Split load across BEs (WAL is local to coordinator BE).
2. `wal-du` on each BE storage path.
3. Prefer dedicated NVMe for `group_commit_wal_path`.
4. A/B `group_commit_data_bytes` (128MB vs 512MB) — size threshold dominates when ingest ≫ interval.
5. `sync_mode` or client throttle for backpressure.

```bash
./scripts/doris-debug wal-du /path/to/be/storage
./scripts/doris-debug log-grep be/log --pack group_commit
```
