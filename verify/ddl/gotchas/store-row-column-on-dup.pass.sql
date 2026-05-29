-- ref: doris-best-practices/SKILL.md:90
-- desc: store_row_column="true" is ACCEPTED on DUPLICATE (Doris 4.x; skill corrected after finding #1)
-- min_version: 4.0
-- mode: any
-- note: exact intro version unconfirmed; tagged 4.0 conservatively (verified on 4.1.1). Older versions were UNIQUE-only.
CREATE TABLE t_srowcol_dup (
    id   BIGINT       NOT NULL,
    name VARCHAR(50)
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "store_row_column" = "true",
    "replication_num" = "1"
);
