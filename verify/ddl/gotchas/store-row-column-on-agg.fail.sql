-- ref: doris-best-practices/SKILL.md:90
-- desc: store_row_column="true" must be rejected on AGGREGATE (confirmed on 4.1.1)
-- min_version: 2.1
-- mode: any
-- errlike: Aggregate table can't support row column
CREATE TABLE t_srowcol_agg (
    k INT    NOT NULL,
    v BIGINT SUM
) AGGREGATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES (
    "store_row_column" = "true",
    "replication_num" = "1"
);
