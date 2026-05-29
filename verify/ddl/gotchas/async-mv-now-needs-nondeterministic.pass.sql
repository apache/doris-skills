-- ref: doris-best-practices/SKILL.md:96
-- desc: async MV using NOW() WITH enable_nondeterministic_function=true must be accepted
-- min_version: 2.1
-- mode: any
CREATE TABLE mvbase_now_ok (
    k  INT      NOT NULL,
    ts DATETIME NOT NULL
) DUPLICATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");

CREATE MATERIALIZED VIEW mv_now_ok
BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 10 MINUTE
DISTRIBUTED BY RANDOM BUCKETS 1
PROPERTIES ("replication_num" = "1", "enable_nondeterministic_function" = "true")
AS SELECT k, ts FROM mvbase_now_ok WHERE ts > NOW();
