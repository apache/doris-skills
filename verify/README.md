# doris-skills verification suite

Regression suite that checks the **factual claims** in the skills against a real
Apache Doris cluster and against `doriscli`. Three layers:

| Layer | What it proves | Tool | Status |
|---|---|---|---|
| **L1 — knowledge** | Every DDL template (T1–T5) and DDL gotcha in `doris-best-practices/SKILL.md` is accepted / rejected exactly as claimed | `mysql` client | ✅ `run.sh` |
| **L2 — CLI contract** | Every command + JSON field in `CLI-CONTRACT.md` really exists in `doriscli` | `doriscli --format json` + `jq` | ✅ `cli/run.sh` |
| **L3 — behavior** | Triggering, evidence-first / safety guardrails, end-to-end DDL that loops back through L1 | `claude` + skill-creator eval harness | ⏳ planned |

## Run L1

```bash
cd verify
cp env.example.sh env.sh   # then edit env.sh with your connection info
./run.sh                   # runs every case under ddl/
./run.sh ddl/gotchas       # run one subdir only
KEEP=1 ./run.sh            # keep the scratch db for inspection
```

`run.sh` connects over the MySQL protocol, creates a throwaway database
(`doris_skill_verify`, dropped at the end — the runner refuses any scratch name
that does not start with that prefix so it can never DROP a real db), runs each
case, and writes a markdown report to `reports/`. Exit code is non-zero if any
case fails, so it drops straight into CI.

## L1 coverage

27 cases: the 5 DDL templates (T1–T5) and the `doris-best-practices/SKILL.md` §2
"DDL hard constraints" matrix — each constraint as a reject case (often with a
matching accept case): BOOLEAN-default quoting, `store_row_column` per model,
`compaction_policy=time_series` per model, inline-vs-PROPERTIES BloomFilter,
AGGREGATE column syntax (agg-fn order, `DEFAULT "null"` type rule), UNIQUE+RANGE
partition-column-in-key, key-columns-prefix order, AUTO PARTITION (`date_trunc`
+ empty parens), dynamic-partition needs a `PARTITION BY` clause,
`enable_unique_key_partial_update` as a (rejected) table property, and async-MV
`REFRESH` syntax / `NOW()` nondeterministic-function rule.

Intentionally **not** L1 cases: claims that are advisory rather than DDL-rejections
(e.g. "don't set `dynamic_partition.buckets`" — Doris does not reject it), and the
runtime-diagnosis / sizing reference rules (those belong to L2/L3). Perf claims
(e.g. prefix-index 36-byte limit effects) need data + measurement, not a DDL probe.

## L2 coverage & finding

`cli/run.sh` seeds a fact+dim dataset, then asserts every command + JSON field that
`../CLI-CONTRACT.md` hard-codes resolves against the live cluster (auto-detecting the
doriscli binary and FE HTTP port). On Doris 4.1.1, **14 pass, 4 fail** — all four
failures are `profile get` operator-level fields (`operators[]`, `query_stats.*`,
`time_breakdown.plan`, `scanned_tables`). `auth status`, `tablet`, `sql`, and
`profile list` fully satisfy the contract.

Root cause of the `profile get` gap (doriscli 0.1.0, **not** the skills):
1. Operator detail needs `profile_level=2` (default is `1`); doriscli's `--profile`
   only sets `enable_profile=true`, so the profile has no operator tree.
2. With `profile_level=2` the operator-rich profile is large (~1.2 MB for a trivial
   join) and doriscli's `resp.json()` (`src/connection/http.rs:195`) fails to decode
   it — the body is valid JSON (verified with jq + python), so the bug is doriscli's.

Effect: the skills' runtime-diagnosis layer (`cli-investigation.md`) reads those
fields, so on 4.1.1 they come back null — exactly the "silently degrades to null"
failure the contract warns about. The suite stays red here until doriscli is fixed.

## How a case works

Each `ddl/**/*.sql` file is one case. The filename suffix is the expectation:

- `*.pass.sql` — Doris must **accept** the DDL (exit 0).
- `*.fail.sql` — Doris must **reject** it. If the case declares `-- errlike: <substr>`,
  the rejection must also contain that substring, so the test verifies it failed
  *for the documented reason* — not because of an unrelated typo.

A leading comment header carries metadata:

```sql
-- ref: doris-best-practices/SKILL.md:97   # the exact claim this verifies
-- desc: BOOLEAN default must be quoted     # human label
-- min_version: 2.1                         # skipped if DORIS_VERSION is older
-- mode: any                                # any | integrated | cloud
-- errlike:                                 # (.fail only) expected error substring
```

`min_version` / `mode` gate version- and deployment-specific claims so a case
that is "correctly rejected because the feature doesn't exist on this version"
doesn't masquerade as a real pass. Skips are reported loudly, not hidden.

## Calibrating `errlike`

New `*.fail.sql` cases ship with an empty `errlike:`. The first run prints the
actual Doris error for each, so you can paste the stable part back into the
header to lock in the reason. Until then, a fail-case passes on "rejected at all".
