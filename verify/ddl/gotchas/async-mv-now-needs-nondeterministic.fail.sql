-- ref: doris-best-practices/SKILL.md:96
-- desc: async MV using NOW() WITHOUT enable_nondeterministic_function must be rejected
-- min_version: 2.1
-- mode: any
-- errlike: enable_nondeterministic_function
CREATE TABLE mvbase_now (
    k  INT      NOT NULL,
    ts DATETIME NOT NULL
) DUPLICATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");

CREATE MATERIALIZED VIEW mv_now_bad
BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 10 MINUTE
DISTRIBUTED BY RANDOM BUCKETS 1
PROPERTIES ("replication_num" = "1")
AS SELECT k, ts FROM mvbase_now WHERE ts > NOW();
