-- ref: doris-best-practices/SKILL.md:95
-- desc: async MV with "REFRESH AUTO ON SCHEDULE EVERY 10 MINUTE" (correct form) must be accepted
-- min_version: 2.1
-- mode: any
CREATE TABLE mvbase_refresh_ok (
    k INT NOT NULL,
    v INT
) DUPLICATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");

CREATE MATERIALIZED VIEW mv_refresh_ok
BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 10 MINUTE
DISTRIBUTED BY RANDOM BUCKETS 1
PROPERTIES ("replication_num" = "1")
AS SELECT k, sum(v) AS sv FROM mvbase_refresh_ok GROUP BY k;
