-- ref: doris-best-practices/SKILL.md:97
-- desc: BOOLEAN default must be quoted — DEFAULT "true" (quoted) must be accepted
-- min_version: 2.0
-- mode: any
CREATE TABLE t_bool_good (
    id   INT      NOT NULL,
    flag BOOLEAN  DEFAULT "true"
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");
