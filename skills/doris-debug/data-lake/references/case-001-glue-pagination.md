---
type: reference
category: data-lake
keywords: [glue, catalog, pagination, NextToken, SHOW DATABASES, AWS]
---

# Case-001: Glue Catalog 只展示部分 Database — Pagination 丢失

## Environment

- Doris version: 26.0.3 (cloud)
- Architecture: storage-compute separation, BYOC
- Catalog type: AWS Glue

## Symptom

`SHOW DATABASES FROM glue_catalog` 只返回前几页的 database，大量 database 未显示。

直接在 AWS Glue API 调用返回完整列表（100+ databases），但 Doris 只展示前 20 个左右。

## Investigation

### Step 1: 对比 Glue API vs Doris

```bash
# AWS Glue API 直接调用
aws glue get-databases --region us-east-1 | jq '.DatabaseList | length'
# 返回: 100+

# Doris 查询
mysql> SHOW DATABASES FROM glue_catalog;
# 返回: 20 rows
```

### Step 2: 代码核对

Glue `GetDatabases` API 的默认 page size 通常是 20 或 50，返回结果包含 `NextToken` 用于请求下一页。

Doris `GlueCatalog.getAllDatabases()` 中：
- 如果未正确处理 `NextToken`
- 或仅调用一次 API 不进行 pagination 循环
- 结果：只返回第一页的 database

### Step 3: 确认 fe.log

```
fe/log/fe.log:
grep -i "GlueCatalog" fe.log
```

如果有 `getAllDatabases` 相关日志，对比返回的 database 数量与 AWS API 实际数量。

## Root Cause

Doris Glue Catalog 的 `getAllDatabases()` 实现未正确处理 AWS Glue API 的 `NextToken` pagination 机制，只获取到第一页数据。

## Fix

- 修复 `GlueCatalog.getAllDatabases()` 增加 pagination 循环：
  ```java
  do {
      GetDatabasesResult result = glueClient.getDatabases(request);
      databases.addAll(result.getDatabaseList());
      request.setNextToken(result.getNextToken());
  } while (request.getNextToken() != null);
  ```

## Key diagnostic actions

1. 对比 AWS Glue API 直接调用结果 vs Doris `SHOW DATABASES` 返回
2. fe.log 搜索 `GlueCatalog` 或 `getAllDatabases` 错误
3. 确认 Glue API 返回的 `NextToken`
4. 如果适用，同样检查 Hive Metastore / Iceberg REST catalog 的 pagination 处理
