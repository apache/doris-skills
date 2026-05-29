-- ref: doris-best-practices/SKILL.md:97
-- desc: BOOLEAN default must be quoted — DEFAULT TRUE (unquoted) must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: mismatched input 'TRUE'
CREATE TABLE t_bool_bad (
    id   INT      NOT NULL,
    flag BOOLEAN  DEFAULT TRUE
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");
