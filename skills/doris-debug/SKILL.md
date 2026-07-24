---
name: doris-debug
description: >
  Apache Doris production diagnostics router. Use when Apache Doris queries are slow,
  imports are failing or timing out, compaction is raising -235 errors, nodes are OOM
  or crashing, materialized views are not rewriting, or tablet/replica health is
  degraded. Routes to the appropriate doris-debug-* skill. Covers shared-nothing and
  cloud (storage-compute separation) deployments.
version: 0.3.0
---

# Doris Debug Router

## How to use

1. Identify the symptom domain from the table below.
2. Read `shared/references/01-common-commands.md` for diagnostic SQL and API commands.
3. Read `shared/references/02-source-map.md` to map symptoms to Apache Doris source code locations.
4. Open the target skill (`<domain>/SKILL.md`) and follow its cause table and decision tree.
5. Check `shared/references/03-case-index.md` for matching production case patterns.

## Skill routing

| Symptom | Skill |
|---------|-------|
| Slow / timeout / hanging query, Profile analysis, Exchange WaitForData | `query/SKILL.md` |
| Stream Load / Broker Load / Routine Load failure, Group Commit WAL pile-up | `import/SKILL.md` |
| -235 / too many versions, compaction score high, compaction lag | `compaction/SKILL.md` |
| BE/FE OOM, crash, false Alive, memory leak | `node/SKILL.md` |
| Sync MV miss, async MTMV refresh/rewrite issues | `materialized-view/SKILL.md` |
| Tablet replica missing, clone backlog, disk skew, tablet repair | `tablet/SKILL.md` |
| FE/BE startup failure, port conflict, priority_networks misconfig | `deployment/SKILL.md` |
| Hive/Iceberg/Paimon/Glue catalog query failure, metadata refresh, S3/HDFS connectivity | `data-lake/SKILL.md` |
| Workload Group queue starvation, CPU/memory isolation leaks, spill issues | `resource-isolation/SKILL.md` |
| Storage-compute separation, meta-service latency, file cache, warmup | `cloud/SKILL.md` |

## Shared references

| Document | Content |
|----------|---------|
| `shared/references/01-common-commands.md` | Diagnostic SQL, HTTP API, and CLI commands |
| `shared/references/02-source-map.md` | Symptom → Doris source code mapping (with version annotations) |
| `shared/references/03-case-index.md` | 45 production case summaries across 8 domains |
| `shared/references/04-metrics-guide.md` | Per-domain key metrics with thresholds |
| `shared/references/05-config-quick-ref.md` | Per-domain key configuration parameters with tuning guidance |
| `shared/guides/` | Cross-module cascade troubleshooting |

## Companion skills

- `doris-profile-reader`: Deep Profile analysis for query bottlenecks (referenced by `query/SKILL.md` Cause C — BE compute bottleneck).
- `doris-best-practices`: Preventive table design and configuration guidance.
- `doris-architecture-advisor`: Workload-aware architecture decisions.

## Methodology

1. Client → FE → BE → Disk/Network top-down investigation
2. Logs / Metrics / Profile / `SHOW PROC` evidence first
3. Stop the bleeding (throttle, kill, `reset_rpc_channel`) before root cause
4. Verify hypotheses against Doris source code (`02-source-map.md`)
5. Match known case patterns (`03-case-index.md`) to avoid rediscovery
