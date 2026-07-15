---
name: doris-debug-query
description: >
  Use for Apache Doris slow/hanging/timeout queries. Covers FE planner (Nereids timeout),
  BE Profile bottlenecks, and Exchange WaitForData / brpc E1008 on port 8060.
  Session vars: enable_profile, query_timeout, nereids_timeout_second.
version: 0.2.0
category: query
---

# Query Troubleshooting

## Causes

| ID | Cause | Evidence |
|----|-------|----------|
| A | Client timeout too small | `query_timeout` vs Profile wall |
| B | Planner | `Nereids cost too much time` / `nereids_timeout_second` |
| C | BE compute (scan/join/spill) | Profile active ExecTime |
| D | Exchange / brpc | WaitForData ≈ timeout; `failed to send brpc when exchange`; `[E1008]` on `:8060` |

## 10 min

```sql
SET enable_profile = true;
-- reproduce
```

```bash
./scripts/doris-debug log-grep fe/log be/log --query-id "$QID" --pack planner
./scripts/doris-debug log-grep be/log --query-id "$QID" --pack exchange
./scripts/doris-debug audit-topk fe/log/fe.audit.log -k 20 --min-ms 5000
```

Planner mitigation (session only): `SET disable_join_reorder=true;` for fat ETL joins; fix stats with `ANALYZE`.

## Cause C — BE compute (scan/join/spill)

When Profile shows high active ExecTime (not Wait\*), route to **doris-profile-reader** for deep Profile analysis:

> **Skill routing**: If `doris-profile-reader` is available, invoke it with the query's Profile to identify which operator (scan/join/agg/spill) dominates. Key indicators to pass:
> - `ActiveTime` per operator
> - `RowsRead` / `ScanBytes` for scan operators
> - `SpillDataSize` if disk spill occurred
> - `JoinType` + `JoinRows` for join operators

Without profile-reader, check directly:
```bash
# Get the Profile text
curl -s "http://$FE:8030/api/query_profile?query_id=$QID"
```

Key Profile counters for Cause C:
| Counter | Meaning | Threshold |
|---------|---------|-----------|
| `ScannerGetBlockTime` | Time reading from storage | > 50% of ExecTime → IO bound |
| `SpillDataSize` | Data spilled to disk | > 0 → memory pressure, check `enable_spill` |
| `JoinProbeTime` | Hash join probe wall time | > 30% → check join order / type |
| `RowsRead` / `ScanBytes` | Scan volume | > 1B rows → check partition pruning |

Profile interpretation: prefer active time over Wait\*.

## Cause D — Exchange / brpc

Code facts (apache/doris):

1. Error text in `be/src/exec/operator/exchange_sink_buffer.h`.
2. `GET /api/reset_rpc_channel/{endpoints}` clears **`brpc_internal_client_cache` only** (`reset_rpc_channel_action.cpp`).
3. `enable_brpc_connection_check` (default false) → `FragmentMgr::_check_brpc_available` hand_shake; consecutive failures erase internal cache.

```bash
curl -s "http://$BE:8040/api/reset_rpc_channel/all"
```

```properties
# be.conf — restart for static DEFINE_Bool
enable_brpc_connection_check = true
brpc_connection_check_timeout_ms = 10000
```

Do not trust ICMP alone. Check `priority_networks`.

## Source

- `SessionVariable.java` — `QUERY_TIMEOUT`, `NEREIDS_TIMEOUT_SECOND`
- Profile WaitForData — exchange source operator
- `exchange_sink_buffer.h`, `reset_rpc_channel_action.cpp`, `fragment_mgr.cpp`
