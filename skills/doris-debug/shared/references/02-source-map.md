# Doris Source Map（排障 ↔ 源码）

> **Baseline version**: Apache Doris 2.1 / 3.0 (2025). Source paths verified against `apache/doris` main branch circa 2025-07.
> For older versions (1.2, 2.0), paths may differ — check your deployed branch's `be/src/common/config.cpp` and `fe/.../SessionVariable.java`.

| 现象 | 源码位置 | 版本提示 | Skill |
|------|----------|----------|-------|
| `failed to send brpc when exchange` | `be/src/exec/operator/exchange_sink_buffer.h` | 2.1+ pipeline engine | query |
| `reset_rpc_channel` 只清 internal cache | `be/src/service/http/action/reset_rpc_channel_action.cpp` | all versions | query |
| brpc stub hand_shake / erase cache | `be/src/runtime/fragment_mgr.cpp` (`_check_brpc_available`) | 2.0+ | query |
| `enable_brpc_connection_check` | `be/src/common/config.cpp` | 2.1+ | query |
| Group Commit finish + `delete_wal` | `be/src/load/group_commit/group_commit_mgr.cpp` | 2.1+ (group_commit is 2.1 feature) | import |
| `group_commit_*` BE 配置 | `be/src/common/config.cpp` (~1407+) | 2.1+ | import |
| TOO_MANY_VERSION / `-235` 文案 | `be/src/storage/rowset_builder.cpp` `check_tablet_version_count` | all versions | compaction / import |
| `max_tablet_version_num` default 2000 | `be/src/common/config.cpp` | all versions | compaction |
| WaitForData counter | exchange source operator Profile | pipeline engine (2.0+) | query |
| Nereids timeout session | `fe/.../qzone/SessionVariable.java` `nereids_timeout_second` | 2.1+ Nereids | query |
| MTMV 服务 | `fe/.../mtmv/MTMVService.java` | 2.1+ | materialized-view |
| Sync MV alter | `fe/.../alter/MaterializedViewHandler.java` | all versions | materialized-view |
| Clone worker pool | `be/src/agent/task_worker_pool.cpp` | all versions | tablet |
| Tablet health proc | `fe/.../master/TabletHealth.java` | all versions | tablet |
| cgroup CPU control | `be/src/util/cgroup_util.cpp` | 2.1+ | resource-isolation |
| Workload Group lifecycle | `fe/.../workloadgroup/WorkloadGroupMgr.java` | 2.1+ | resource-isolation |
| File cache (cloud) | `be/src/io/cache/whole_file_cache.cpp` | 3.0+ (cloud) | cloud |
| Compute Group | `fe/.../cloud/ComputeGroupMgr.java` | 3.0+ (cloud) | cloud |
| S3 connector | `be/src/io/fs/s3/S3FileSystem.cpp` | all versions | data-lake / cloud |
| MemTrackerLimiter | `be/src/runtime/memory/mem_tracker_limiter.cpp` | all versions | node |
| BE startup / port bind | `be/src/service/doris_main.cpp` | all versions | deployment |
| FE bootstrap | `fe/.../master/Env.java` | all versions | deployment |

### Upgrade caveats

- **1.2 → 2.0**: Pipeline engine became default. Old non-pipeline profiles lack `WaitForData`.
- **2.0 → 2.1**: Group Commit async_mode introduced. `group_commit_*` config keys not present in 2.0.
- **2.1 → 3.0**: Cloud mode / compute groups introduced. `meta_service_endpoint` and `file_cache_path` replace some shared-nothing config.

排障结论应能在源码中找到对应错误字符串或配置项；如果找不到，先确认 Doris 版本和分支。
