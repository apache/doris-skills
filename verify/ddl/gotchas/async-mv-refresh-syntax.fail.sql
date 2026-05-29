-- ref: doris-best-practices/SKILL.md:95
-- desc: async MV with "REFRESH SCHEDULE EVERY" (missing AUTO/COMPLETE + ON) must be rejected
-- min_version: 2.1
-- mode: any
-- errlike: mismatched input 'SCHEDULE'
CREATE TABLE mvbase_refresh (
    k INT NOT NULL,
    v INT
) DUPLICATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");

CREATE MATERIALIZED VIEW mv_refresh_bad
REFRESH SCHEDULE EVERY 10 MINUTE
DISTRIBUTED BY RANDOM BUCKETS 1
PROPERTIES ("replication_num" = "1")
AS SELECT k, sum(v) AS sv FROM mvbase_refresh GROUP BY k;
