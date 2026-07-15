---
name: doris-debug-data-lake
description: >
  Use for Doris external catalog issues: Hive/Iceberg/Paimon/Hudi query failures,
  metadata refresh, filesystem S3/HDFS connectivity, external MV rewrite misses.
version: 0.2.0
category: data-lake
---

# Data Lake (Multi-Catalog)

## Causes

| ID | Cause | Evidence | Source anchor |
|----|-------|----------|---------------|
| A | Metadata stale | Query returns old data / missing partitions after upstream write | `HMSClient.java`, `CachedHMSClient.java` |
| B | S3/HDFS connectivity | `Access Denied`, `Timeout`, `NoSuchBucket` | `S3FileSystem.java`, `HdfsResource.java` |
| C | External MV rewrite miss | EXPLAIN shows no MATERIALIZED_REWRITE | `MTMVService.java` rewrite rules |
| D | Schema mismatch | Parquet/ORC schema ≠ Hive Metastore schema | `ParquetReader.cpp`, schema merge |
| E | Credential / IAM expiry | STS / IAM token rotated; 403 on S3 | `S3FileSystem.java` credential refresh |
| F | Too many open files | FD exhaustion listing large table directories | BE `ulimit -n`, `FileSystem.listFiles()` |

## 10 min triage

```sql
-- Verify catalog is alive
SHOW CATALOGS;

-- Refresh metadata (hive / iceberg / paimon)
REFRESH CATALOG hive_catalog;
REFRESH DATABASE hive_catalog.db_name;
REFRESH TABLE hive_catalog.db_name.tbl_name;

-- Check if external MV rewrite is enabled
SET materialized_view_rewrite_enable_contain_external_table = true;

-- Analyze external table for CBO stats
ANALYZE TABLE hive_catalog.db_name.tbl_name;
```

```bash
# BE logs for S3/HDFS errors
./scripts/doris-debug log-grep be/log --query-id "$QID"
grep -r "403\|Access Denied\|Timeout\|NoSuchBucket\|Token.*expired" be/log/

# Check BE file descriptor limit
cat /proc/$BE_PID/limits | grep "open files"
```

## Cause A — Metadata staleness

Hive Metastore metadata is cached; `REFRESH CATALOG` invalidates the cache. For large catalogs, prefer:

```sql
-- Refresh only the changed partition
REFRESH TABLE catalog.db.tbl PARTITION (dt='2026-07-15');
```

If refresh is slow, check HMSClient cache settings (`fe.conf`):
```properties
hive_metastore_client_timeout_second = 10
```

## Cause B — S3/HDFS connectivity

```properties
# be.conf — S3 credential chain
aws_access_key_id = ...
aws_secret_access_key = ...
aws_region = us-east-1
```

```bash
# Test S3 reachability from BE host
curl -I "https://<bucket>.s3.<region>.amazonaws.com"
```

```properties
# fe.conf for HDFS catalog
hadoop_conf_dir = /path/to/hadoop/conf  # must contain core-site.xml + hdfs-site.xml
```

## Cause E — Credential rotation

For STS/AssumeRole-based S3 access, the cached credential may expire:
```sql
-- Force credential refresh (Doris 2.1+ / 3.0)
REFRESH CATALOG hive_catalog;
```

For long-running queries against external tables, ensure credential TTL > query timeout.

## Source

- `fe/.../datasource/hive/HMSExternalCatalog.java`
- `fe/.../datasource/hive/HMSClient.java`
- `be/src/io/fs/s3/S3FileSystem.cpp` — S3 connector
- `be/src/io/fs/hdfs/HdfsFileSystem.cpp` — HDFS connector
- `be/src/vec/exec/format/parquet/vparquet_reader.cpp` — parquet reader
- `fe/.../mtmv/MTMVService.java` — external MV rewrite
