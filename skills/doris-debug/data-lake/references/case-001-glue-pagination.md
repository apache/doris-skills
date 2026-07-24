---
type: reference
category: data-lake
keywords: [glue, catalog, pagination, NextToken, SHOW DATABASES, AWS]
---

# Case-001: Glue Catalog Shows Only Some Databases — Pagination Lost

## Environment

- Doris version: 26.0.3 (cloud)
- Architecture: storage-compute separation, BYOC
- Catalog type: AWS Glue

## Symptom

`SHOW DATABASES FROM glue_catalog` returns only the first few pages of databases; a large number of databases are not shown.

Calling the AWS Glue API directly returns the complete list (100+ databases), but Doris only shows about the first 20.

## Investigation

### Step 1: Compare Glue API vs Doris

```bash
# Direct AWS Glue API call
aws glue get-databases --region us-east-1 | jq '.DatabaseList | length'
# Returns: 100+

# Doris query
mysql> SHOW DATABASES FROM glue_catalog;
# Returns: 20 rows
```

### Step 2: Code Review

The default page size of the Glue `GetDatabases` API is usually 20 or 50, and the response includes a `NextToken` for requesting the next page.

In Doris `GlueCatalog.getAllDatabases()`:
- If `NextToken` is not handled correctly
- or the API is called only once without a pagination loop
- Result: only the first page of databases is returned

### Step 3: Check fe.log

```
fe/log/fe.log:
grep -i "GlueCatalog" fe.log
```

If there are `getAllDatabases`-related logs, compare the number of databases returned with the actual count from the AWS API.

## Root Cause

The Doris Glue Catalog's `getAllDatabases()` implementation does not correctly handle the AWS Glue API's `NextToken` pagination mechanism and only fetches the first page of data.

## Fix

- Fix `GlueCatalog.getAllDatabases()` by adding a pagination loop:
  ```java
  do {
      GetDatabasesResult result = glueClient.getDatabases(request);
      databases.addAll(result.getDatabaseList());
      request.setNextToken(result.getNextToken());
  } while (request.getNextToken() != null);
  ```

## Key diagnostic actions

1. Compare the result of calling the AWS Glue API directly vs Doris `SHOW DATABASES`
2. Search fe.log for `GlueCatalog` or `getAllDatabases` errors
3. Confirm the `NextToken` returned by the Glue API
4. If applicable, also check pagination handling in Hive Metastore / Iceberg REST catalogs
