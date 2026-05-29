---
title: Getting Started — Self-Hosted / BYOC
tags: [start, self-hosted, byoc, on-prem, setup]
---
## Getting Started — Self-Hosted / BYOC / On-Prem

### Where to Find Connection Details

**MySQL host + port**: the FE node address and MySQL protocol port. Default port is `9030`. Check `fe.conf` → `mysql_service_port` or ask your DBA.

**HTTP port**: FE HTTP port for profile fetching and REST API. Self-hosted Apache Doris uses `8030` by default; Apache Doris cloud mode uses `8080`. Check `fe.conf` → `http_port`. If unsure, `doriscli auth add` probes 8080/8030/8040 and shows suggestions.

**User + password**: default root user is `root` with empty password on fresh installs. Production clusters should have a password set via `SET PASSWORD`.

### Prerequisites
- FE nodes: Java 8+ runtime
- BE nodes: Linux with sufficient disk, memory
- Network: FE and BE nodes must be able to communicate

### Deployment Steps
1. Deploy FE nodes (1 Leader + 2 Followers for HA)
2. Deploy BE nodes (3+ for production)
3. Register BEs with FE: `ALTER SYSTEM ADD BACKEND "<be_host>:9050";`
4. Create database and tables

### Connect with the doriscli management CLI (optional)
```bash
doriscli auth add local --host <fe_host> --port 9030 --http-port 8030 --user root --password "$DORIS_PASSWORD"
doriscli use local
doriscli auth status --format json
```

### Connect via MySQL client (always available)
```bash
mysql -h <fe_host> -P 9030 -u root -p"$DORIS_PASSWORD"
```
### Self-Hosted Properties
```sql
PROPERTIES ("replication_num" = "3");  -- 3 replicas for HA
```
Reference: [Apache Doris Installation](https://doris.apache.org/docs/install/cluster-deployment/standard-deployment)
