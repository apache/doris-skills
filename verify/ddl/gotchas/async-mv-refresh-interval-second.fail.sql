-- ref: doris-best-practices/SKILL.md:95
-- desc: async MV refresh interval below the 1-MINUTE minimum (EVERY 30 SECOND) must be rejected
-- min_version: 2.1
-- mode: any
-- errlike: interval time unit can not be second
-- Isolates ONLY the interval unit: identical to async-mv-refresh-syntax.pass.sql
-- except "10 MINUTE" -> "30 SECOND". SKILL.md:95 "Minimum interval: 1 MINUTE";
-- schema-ddl-gotchas.md gotcha #8 (SECOND not supported).
CREATE TABLE mvbase_interval (
    k INT NOT NULL,
    v INT
) DUPLICATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");

CREATE MATERIALIZED VIEW mv_interval_second
BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 30 SECOND
DISTRIBUTED BY RANDOM BUCKETS 1
PROPERTIES ("replication_num" = "1")
AS SELECT k, sum(v) AS sv FROM mvbase_interval GROUP BY k;
