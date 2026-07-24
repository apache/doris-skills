---
type: reference
category: compaction
keywords: [base compaction, schema change, SC residue, tablet state, compaction score ghost]
---

# Case-002: Schema Change Residue Causes Inflated Base Compaction Score

## Environment

- Doris version: cloud 4.0+
- Architecture: storage-compute separation

## Symptom

Grafana monitoring shows the base compaction score of one BE staying persistently high:
- base score: max 1490, avg 1370
- cumu score: max 79, avg 32.5 (normal)

The alert fires but the cluster has no query anomalies. The user suspects insufficient compaction resources.

## Key evidence

```
be/log:
get_topn_compaction_score ... type=1  → high score (base)
get_topn_compaction_score ... type=2  → normal score (cumu)
```

However, the number of compaction tasks actually submitted by `get_topn_tablets_to_compact()` is not proportional to the score.

The Grafana screenshot covers 2026-07-01 to 07-07; the base score rises slowly rather than spiking.

Historical check: the same cluster has Schema Change operation records.

## Investigation

### Step 1: Distinguish Base vs Cumulative

Doris compaction enums:
```
BASE_COMPACTION = 1       → base score
CUMULATIVE_COMPACTION = 2 → cumu score
```

`get_topn_compaction_score ... type=1` is the base score, `type=2` is cumu. They must not be mixed up.

Currently base is high while cumu is normal → base compaction is blocked; this is not a global shortage of compaction resources.

### Step 2: Code Review

The cloud scheduler calls `get_topn_tablets_to_compact()` to compute the highest-scoring tablet and writes the value into:
```
tablet_base_max_compaction_score    → Grafana metric source
tablet_cumulative_max_compaction_score
```

But updating the score does not equal actually picking a tablet for execution. Before picking, the scheduler checks:
- whether tablet_state allows compaction
- whether a slot is available
- whether the SC (Schema Change) context permits it
- other filter conditions

### Step 3: Filter Condition Analysis

The SC operation created base compaction candidates on the tablet (because SC generates new rowsets that need merging), but when the SC context has not been cleaned up, `tablet_state` or the SC state blocks compaction from executing.

Result: the base score keeps being computed and written to the metric → Grafana alerts, but compaction never actually runs → the score never gets relieved.

## Root Cause

Residual SC context left by Schema Change operations prevents base compaction candidate tablets from being executed by the compaction scheduler.

This is not "insufficient compaction resources" or "too many cumu points" — it is "candidates exist but are not allowed to execute."

## Fix

1. Clean up residual SC context (`SHOW ALTER TABLE` to confirm SC status → `CANCEL ALTER` to clean up)
2. Review the SC-related condition checks in the compaction scheduling filter logic
3. Do not blindly increase compaction threads or disk concurrency — the issue is filtered candidates, not thread/IO shortage

## Key diagnostic actions

1. Distinguish base (type=1) vs cumu (type=2) scores (different problem directions)
2. `SHOW ALTER TABLE` to check for pending/failed SC operations
3. Search be/log for `get_topn_tablets_to_compact` → confirm the filter logic
4. If the base score is high but no high-scoring tablet can be found (C5 scenario), check cloud scheduling slots/state/filter conditions
5. `SHOW PROC '/cluster_health/tablet_health'` to confirm whether any tablet has version anomalies
