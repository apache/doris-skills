-- ref: doris-best-practices/SKILL.md:99
-- desc: AGGREGATE column needs agg-function BEFORE default — DEFAULT "0" SUM (wrong order) must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: extraneous input 'SUM'
CREATE TABLE t_agg_deforder (
    k DATE   NOT NULL,
    v BIGINT DEFAULT "0" SUM
) AGGREGATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");
