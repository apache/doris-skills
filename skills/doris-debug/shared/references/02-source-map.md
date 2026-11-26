# Doris Source Map (Troubleshooting ↔ Source Code)

> **Baseline**: Apache Doris 3.x–5.x. Paths below were re-verified against
> `apache/doris` master `6261b18` (2026-11-25).
> Older or newer branches may differ: confirm any path with
> `git grep -n "<symbol>" -- be/src fe` in the checkout of the branch you actually run,
> and check that branch's `be/src/common/config.cpp` and
> `fe/fe-common/src/main/java/org/apache/doris/common/Config.java` for config items.

| Symptom | Source Location | Version Notes | Skill |
|------|----------|----------|-------|
| `failed to send brpc when exchange` | `be/src/exec/operator/exchange_sink_buffer.h` | 2.1+ pipeline engine | query |
| `reset_rpc_channel` only clears internal cache | `be/src/service/http/action/reset_rpc_channel_action.cpp` | all versions | query |
| brpc stub hand_shake / erase cache | `be/src/runtime/fragment_mgr.cpp` (`_check_brpc_available`) | 2.0+ | query |
| `enable_brpc_connection_check` | `be/src/common/config.cpp` | 2.1+ | query |
| Group Commit finish + `delete_wal` | `be/src/load/group_commit/group_commit_mgr.cpp` | 2.1+ (group_commit is 2.1 feature) | import |
| `group_commit_*` BE configs | `be/src/common/config.cpp` | 2.1+ | import |
| TOO_MANY_VERSION / `-235` error message | `be/src/storage/rowset_builder.cpp` (`check_tablet_version_count`) | all versions | compaction / import |
| `max_tablet_version_num` default 2000 | `be/src/common/config.cpp` | all versions | compaction |
| WaitForData counter | exchange source operator Profile (`be/src/exec/operator/exchange_source_operator.cpp`) | pipeline engine (2.0+) | query |
| Nereids timeout session | `fe/fe-core/src/main/java/org/apache/doris/qe/SessionVariable.java` (`nereidsTimeoutSecond`) | 2.1+ Nereids | query |
| MTMV service | `fe/fe-core/src/main/java/org/apache/doris/mtmv/MTMVService.java` | 2.1+ | materialized-view |
| Sync MV alter | `fe/fe-core/src/main/java/org/apache/doris/alter/MaterializedViewHandler.java` | all versions | materialized-view |
| Clone worker pool | `be/src/agent/task_worker_pool.cpp` | all versions | tablet |
| Tablet health proc | `fe/fe-core/src/main/java/org/apache/doris/common/proc/TabletHealthProcDir.java` | `TabletHealth.java` no longer exists on master | tablet |
| cgroup CPU control | `be/src/util/cgroup_util.cpp` | 2.1+ | resource-isolation |
| Workload Group lifecycle | `fe/fe-core/src/main/java/org/apache/doris/resource/workloadgroup/WorkloadGroupMgr.java` | 2.1+ | resource-isolation |
| File cache (cloud) | `be/src/io/cache/block_file_cache.cpp` | `whole_file_cache.cpp` no longer exists on master (block file cache) | cloud |
| Compute Group | `fe/fe-core/src/main/java/org/apache/doris/resource/computegroup/ComputeGroupMgr.java` | 3.0+ (cloud) | cloud |
| S3 / object storage connector | `be/src/io/fs/obj_storage_file_system.cpp` (clients: `be/src/io/object_storage/`) | `io/fs/s3/S3FileSystem.cpp` no longer exists on master | data-lake / cloud |
| MemTrackerLimiter | `be/src/runtime/memory/mem_tracker_limiter.cpp` | all versions | node |
| BE startup / port bind | `be/src/service/doris_main.cpp` | all versions | deployment |
| FE bootstrap | `fe/fe-core/src/main/java/org/apache/doris/catalog/Env.java` | all versions | deployment |
| FE heartbeat handling | `fe/fe-core/src/main/java/org/apache/doris/system/HeartbeatMgr.java` | `HeartbeatHandler.java` no longer exists on master | node |

### Upgrade caveats

- **1.2 → 2.0**: Pipeline engine became default. Old non-pipeline profiles lack `WaitForData`.
- **2.0 → 2.1**: Group Commit async_mode introduced. `group_commit_*` config keys not present in 2.0.
- **2.1 → 3.0**: Cloud mode / compute groups introduced. `meta_service_endpoint` and `file_cache_path` replace some shared-nothing config.
- **3.x/4.x → 5.x**: whole-file cache was replaced by the block file cache, and several memory knobs were renamed or removed — see `05-config-quick-ref.md` for the per-parameter status.

Troubleshooting conclusions should map to a corresponding error string or config item in the source code; if not found, first confirm the Doris version and branch.
