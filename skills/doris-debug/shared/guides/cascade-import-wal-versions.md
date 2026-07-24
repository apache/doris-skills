# Cascade: High-Throughput Async Group Commit ↔ WAL ↔ Versions

```
group_commit:async_mode high MB/s
 → receiving BE local WAL grows
 → group commit throughput < ingest rate
 → version_count → max_tablet_version_num → TOO_MANY_VERSION
 → Compaction / query degradation
```

Skill: `import` → `compaction`  
Code: `group_commit_mgr.cpp`, `rowset_builder.cpp`  
Tool: `./scripts/doris-debug wal-du <storage_root>`
