# Doris Common Diagnostic Commands

Default ports (subject to conf): FE HTTP `8030` / MySQL `9030`; BE HTTP `8040` / brpc `8060`.

## SQL

```sql
SHOW FRONTENDS\G
SHOW BACKENDS\G
SHOW PROC '/backends';
SHOW PROC '/cluster_health/tablet_health';
SHOW LOAD ORDER BY CreateTime DESC LIMIT 30;
SHOW TABLETS FROM db.tbl;
ADMIN SHOW REPLICA STATUS FROM db.tbl;
SET enable_profile = true;
```

Top-N slow queries can be read from the FE audit table instead of reshaping log files
(table and columns as defined in `fe/fe-core/src/main/java/org/apache/doris/catalog/InternalSchemaInitializer.java`):

```sql
SELECT `query_id`, `time`, `query_time`, `state`, `user`, `db`
FROM __internal_schema.audit_log
WHERE query_time >= 5000
ORDER BY query_time DESC
LIMIT 20;
```

## BE HTTP endpoints

These paths are registered in `be/src/service/http_service.cpp` on apache/doris master
(`6261b18`, 2026-11-25). `GET /metrics` requires no authorization
(`TPrivilegeType::NONE`); the admin endpoints may require an admin user.

| Endpoint | Returns |
|---|---|
| `GET /metrics` | Prometheus-format BE metrics (compaction, memory, cache, S3, ...) |
| `GET /api/compaction_score` | Per-tablet compaction scores (admin) |
| `GET /api/compaction/show` | Compaction status (admin) |
| `GET /api/file_cache` | File cache statistics, cloud mode (admin) |
| `GET /api/show_config` | Full BE config as JSON |
| `GET /api/be_version_info` | BE version |
| `GET /tablets_json` | Tablet report JSON (admin) |
| `GET /api/reset_rpc_channel/{endpoints}` | Reset brpc channels to the given endpoints (admin) |

```bash
# One metric family (replace the pattern as needed)
curl -s "http://$BE:8040/metrics" | grep -E "compaction"

# One config value
curl -s "http://$BE:8040/api/show_config" | grep -o '"mem_limit": *"[^"]*"'

# brpc channel reset (see doris-debug-query Cause D)
curl -s "http://$BE:8040/api/reset_rpc_channel/all"
```

`/metrics` is a full scrape: always pipe it through `grep -E` and scope the pattern to one
family. This repository ships no helper script for BE metrics; the `curl` form above is the
supported path.

## Log grep

The Doris logs are the primary evidence source. Filter by query id where the id is
logged, otherwise by the message strings the source emits.

Paths below (`be/log/...`, `fe/log/...`) are relative to a deployment root that contains
both `fe/` and `be/` directories, as in the all-in-one image. For a source installation,
the logs live under each node's `DORIS_HOME`: `$DORIS_HOME/log/be.INFO` for a BE and
`$DORIS_HOME/log/fe.log` for an FE.

| Pack | Message pattern | Source anchor |
|---|---|---|
| `versions` | `exceed limit` / `version count:` | `be/src/storage/rowset_builder.cpp` |
| `memory` | `memory tracker limit exceeded` | `be/src/runtime/memory/mem_tracker_limiter.cpp` |
| `group_commit` | `Too many group commit async WALs` / `group commit` | `be/src/load/group_commit/group_commit_mgr.cpp` |
| `exchange` | `failed to send brpc when exchange` | `be/src/exec/operator/exchange_sink_buffer.h` |

```bash
# All BE INFO lines that carry the query id
grep -rh "$QID" be/log/be.INFO*

# Version pressure (TOO_MANY_VERSION / -235)
grep -hE "exceed limit|version count:" be/log/be.INFO* | tail -20

# Memory pressure
grep -hE "memory tracker limit exceeded" be/log/be.WARNING* | tail -20

# Group commit / WAL pile-up
grep -hE "Too many group commit async WALs|group commit" be/log/be.INFO* | tail -50

# FE and BE lines for one query (the FE log carries the id for some statements only;
# when it does not, read the plan from the profile instead, see doris-profile-reader)
grep -h "$QID" fe/log/fe.log
grep -rh "$QID" be/log/be.INFO*
```

## WAL disk usage

Group-commit WAL directories come from the BE config `group_commit_wal_path`
(semicolon-separated absolute paths). When it is empty the default is
`<storage_root>/wal` for every BE storage path
(`be/src/load/group_commit/wal/wal_manager.cpp`). The directories in use are logged at
startup as `wal_dir:`.

```bash
# Configured value (empty means the default layout below)
curl -s "http://$BE:8040/api/show_config" | grep -o '"group_commit_wal_path": *"[^"]*"'

# Authoritative list, from the BE log
grep -h "wal_dir:" be/log/be.INFO* | tail -10

# Usage of the default layout
du -sh "$BE_STORAGE_ROOT"/wal/*
```
