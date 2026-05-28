---
title: Always Use Merge-on-Write for UNIQUE Tables
impact: CRITICAL
impactDescription: "MoR (default before 2.1) causes slow reads due to merge-sort at query time"
tags: [schema, model, unique, mow, mor]
---

## Always Use Merge-on-Write (MoW) for UNIQUE Tables

**Impact: CRITICAL — MoR requires runtime merge-sort, making reads 2-10× slower.**

Since Doris 2.1, MoW is the default. For older versions, always set explicitly:

```sql
PROPERTIES ("enable_unique_key_merge_on_write" = "true")
```

**MoW vs MoR:**

| Feature | MoW | MoR |
|---------|-----|-----|
| Read speed | Fast (pre-merged) | Slow (merge at query) |
| Write speed | Slightly slower | Faster writes |
| DELETE support | Yes | Yes |
| Partial update | Yes | Limited |

**Always use MoW** unless you have a write-heavy workload with minimal reads.

Reference: [Unique Key Model](https://doris.apache.org/docs/table-design/data-model/unique)
