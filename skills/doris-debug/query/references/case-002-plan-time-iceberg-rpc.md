---
type: reference
category: query
keywords: [plan time, nereids, iceberg, create scan range, catalog rpc, slow query]
---

# Case-002: FE Plan Time 10 Minutes (Iceberg External Table Create Scan Range RPC Explosion)

## Environment

- Doris version: 4.1.3 (Nereids optimizer)
- Architecture: shared-nothing
- Catalog type: Iceberg external catalog

## Symptom

The SQL `SELECT * FROM iceberg.db.table WHERE lower(name) NOT LIKE '%xxx%'` took 10 minutes 8 seconds.
The same query took ~10 minutes on every execution. The user suspected slow BE execution or slow S3 reads.

## Key evidence (Profile)

```
Profile ID: a6e9d417718d4cf6-88857f81140da87f

Total:                         10min8sec
  Plan Time:                   10min8sec    ← 100% of total
    Nereids Translate Time:    10min8sec
    Finalize Scan Node Time:   10min8sec
    Create Scan Range Time:    10min1sec    ← core cost
    Get Splits Time:           6sec323ms

  Schedule Time:               4ms
  Wait and Fetch Result Time:  214ms
  Fetch Result Time:           213ms

FILE_SCAN_OPERATOR:
  ExecTime:                    211.882ms    ← BE execution is only 200ms
  RowsProduced:                540
  ScanRows:                    593
  ScanBytes:                   1021.08 KB
  FileNumber:                  64
  partitions:                  63

Is Nereads:                    Yes
Is Cached:                     No
```

**Conclusion: BE execution is only 214ms/1MB; the problem is entirely in the FE planning phase.**

## Investigation

### Step 1: Confirm the Plan Time share

`Plan Time=10min8sec` equals Total, and BE `ExecTime=211ms`, ruling out BE compute / IO bottlenecks.

### Step 2: Break down the Nereids planning phases

`Nereids Translate Time` = 10min8sec → not an FE lock / GC issue (`Garbage Collect During Plan Time=52sec` is only a small part).

`Finalize Scan Node Time` = 10min8sec → the problem is in the finalize scan node phase.

`Create Scan Range Time` = 10min1sec → creating scan ranges is the core cost.

`Get Splits Time` = 6sec → fetching file splits took only 6 seconds.

### Step 3: Code verification

In the 4.1.3 code, the Iceberg catalog during the Create Scan Range phase:

1. Iterates over every partition (64 files / 63 partitions)
2. Each `getManifestFiles()` call → invokes `UpdateRunningStatus()` → triggers an `msClient.updateInstance()` RPC to the meta-service
3. Each RPC takes about 200ms
4. Repeated calls accumulate → 10min+

```
CreateScanRange
  → for each partition:
      → getManifestFiles()
        → UpdateRunningStatus()
          → msClient.updateInstance()   ← ~200ms RPC each time
```

This is unrelated to BE S3 list or scan; it is purely too many RPCs between FE and the meta-service.

## Root Cause

In Nereids' handling of Iceberg external tables during the Create Scan Range phase, an unnecessary meta-service RPC (`updateInstance`) is made on every manifest file fetch, and this RPC runs once per partition. 64 files × ~200ms each → 10 minutes.

## Fix

- **Short term**: Increase `iceberg_manifest_cache_refresh_interval_s` to reduce the frequency of manifest re-fetching
- **Long term**: Improve the Create Scan Range phase to reduce duplicate RPC calls to the meta-service (batch the fetches, or remove the unnecessary `updateInstance` calls)

## Key diagnostic actions

1. Profile → confirm the `Plan Time` share (rather than BE ExecTime)
2. Confirm `Is Nereids=Yes`
3. Break down the Plan Time sub-phases: `Nereids Translate Time` → `Finalize Scan Node Time` → `Create Scan Range Time`
4. Compare `Get Splits Time` (normal) with `Create Scan Range Time` (abnormal) to confirm the problem is in creating scan ranges, not in fetching the file list
5. For Iceberg/Hive external tables → check manifest/catalog RPC latency
