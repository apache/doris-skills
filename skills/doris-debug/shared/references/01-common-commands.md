# Doris 公共诊断命令

端口默认（以 conf 为准）：FE HTTP `8030` / MySQL `9030`；BE HTTP `8040` / brpc `8060`。

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

```bash
# CLI helpers from this repo
./scripts/doris-debug be-metrics --be http://$BE:8040
./scripts/doris-debug log-grep $BE_LOG_DIR --pack exchange --query-id "$QID"
curl -s "http://$BE:8040/api/reset_rpc_channel/all"
```
