-- ref: doris-best-practices/references/schema-ddl-gotchas.md:131
-- desc: BOOLEAN DEFAULT "null" (string "null" as a boolean default) must be rejected — gotcha #11
-- min_version: 2.0
-- mode: any
-- errlike: Invalid BOOLEAN literal: null
-- Complements bool-default-quoted.fail.sql (which covers the unquoted DEFAULT TRUE
-- variant). gotcha #11 lists BOTH `DEFAULT TRUE` and `DEFAULT "null"` as hard errors.
CREATE TABLE t_bool_null (
    id        INT     NOT NULL,
    is_active BOOLEAN DEFAULT "null"
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");
