# Case: Group Commit WAL pile-up under ~800MB/s Stream Load

## Symptom
async_mode WAL grows; drain lag. Props: interval_ms=2000, data_bytes=256MB. Compaction throughput looks high.

## Root cause
Per-BE WAL ingest > group commit delete rate; size threshold fires ~0.3s; compaction GB/s ≠ WAL drain.

## Fix direction
Spread BEs; dedicated WAL disk; tune data_bytes; check WAL usage with `grep -h "wal_dir:" be/log/be.INFO*` plus `du -sh` on those dirs (see `01-common-commands.md`); optional sync_mode backpressure.

Source: `group_commit_mgr.cpp` delete_wal after successful commit.
