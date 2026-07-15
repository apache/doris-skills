---
name: doris-debug-deployment
description: >
  Use for Doris FE/BE startup failures, port conflicts, priority_networks misrouting,
  meta_dir corruption, and ADD/DROP BACKEND issues.
version: 0.2.0
category: deployment
---

# Deployment & Startup

## Causes

| ID | Cause | Evidence | Source anchor |
|----|-------|----------|---------------|
| A | Port conflict | BE/FE fail to bind; `Address already in use` | `brpc/server.cpp`, `doris_main.cpp` |
| B | `priority_networks` misconfig | brpc connection refused / wrong interface | `config.cpp` |
| C | meta_dir / storage_root_path not writable | `Permission denied` / `No such file` at startup | `olap/olap_meta.cpp` |
| D | FE metadata corruption | FE fails to start after crash; `meta/image.*` errors | `Image.java`, `BDBJEJournal.java` |
| E | Mixed version cluster | Protocol mismatch in thrift/brpc between FE-BE | `be/src/agent/`, `heartbeat` |
| F | DNS / hostname resolution | `UnknownHostException`, BE heartbeat to wrong address | `Env.java` frontend host check |

## 10 min triage

```bash
# FE status
curl -s "http://$FE:8030/api/bootstrap"
curl -s "http://$FE:8030/api/health"

# BE status
curl -s "http://$BE:8040/api/health"

# Port check
ss -tlnp | grep -E "8030|8040|8060|9030"
```

```sql
-- Cluster membership
SHOW FRONTENDS\G
SHOW BACKENDS\G
```

## Cause A — Port conflict

Default ports (from `fe/conf/fe.conf` and `be/conf/be.conf`):

| Service | Port | Config key |
|---------|------|------------|
| FE HTTP | 8030 | `http_port` |
| BE HTTP | 8040 | `webserver_port` |
| BE brpc | 8060 | `brpc_port` |
| FE MySQL | 9030 | `query_port` |
| FE Edit log | 9010 | `edit_log_port` |

```bash
# Kill stale process on target port
fuser -k 8060/tcp  # BE brpc
# Then restart BE
```

## Cause B — priority_networks

The most common cause of "BE shows Alive=true but brpc fails." `priority_networks` tells BE which network interface to bind brpc to.

```properties
# be.conf — match ONE subnet exactly
priority_networks = 10.0.0.0/24
```

Check what interface BE actually bound:
```bash
curl -s "http://$BE:8040/api/health" | grep -o '"ip":"[^"]*"'
```

Validation: the IP in `SHOW BACKENDS` must be reachable from every FE and every other BE on port 8060.

## Cause D — FE metadata recovery

```bash
# Check FE meta directory
ls -la fe/doris-meta/image/
ls -la fe/doris-meta/bdb/

# If bdb is corrupt and this is a follower/observer:
# 1. Remove the bad FE from the cluster
# 2. Wipe doris-meta/
# 3. Re-add as a new follower: ALTER SYSTEM ADD FOLLOWER "host:9010"
```

Never remove `doris-meta/` on the **last healthy Master** FE.

## Source

- `fe/conf/fe.conf` — port defaults
- `be/src/common/config.cpp` — `priority_networks`
- `be/src/service/doris_main.cpp` — BE startup
- `fe/.../master/Env.java` — FE bootstrap
- `fe/.../journal/bdbje/BDBJEJournal.java`
