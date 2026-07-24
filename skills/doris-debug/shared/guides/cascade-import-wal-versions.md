# 级联：高吞吐 async Group Commit ↔ WAL ↔ 版本

```
group_commit:async_mode 高 MB/s
 → 接收 BE 本地 WAL 上涨
 → group commit 吞吐 < 写入
 → version_count → max_tablet_version_num → TOO_MANY_VERSION
 → Compaction / 查询恶化
```

Skill：`import` → `compaction`  
代码：`group_commit_mgr.cpp`、`rowset_builder.cpp`  
工具：`./scripts/doris-debug wal-du <storage_root>`
