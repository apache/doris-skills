# doris-skills verification suite

Regression suite that checks the **factual claims** in the skills against a real
Apache Doris cluster and against `doriscli`. Three layers:

| Layer | What it proves | Tool | Status |
|---|---|---|---|
| **L1 — knowledge** | Every DDL template (T1–T5) and DDL gotcha in `doris-best-practices/SKILL.md` is accepted / rejected exactly as claimed | `mysql` client | ✅ `run.sh` |
| **L2 — CLI contract** | Every command + JSON field in `CLI-CONTRACT.md` really exists in `doriscli` | `doriscli --format json` + `jq` | ✅ `cli/run.sh` |
| **L3 — behavior** | Triggering, evidence-first / safety guardrails, end-to-end DDL that loops back through L1 | nested `claude -p` | 🟡 `behavior/run.sh` (v1) |

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

29 cases: the 5 DDL templates (T1–T5) and the `doris-best-practices/SKILL.md` §2
"DDL hard constraints" matrix — each constraint as a reject case (often with a
matching accept case): BOOLEAN-default quoting (unquoted `TRUE` and the invalid
`DEFAULT "null"` literal), `store_row_column` per model,
`compaction_policy=time_series` per model, inline-vs-PROPERTIES BloomFilter,
AGGREGATE column syntax (agg-fn order, `DEFAULT "null"` type rule), UNIQUE+RANGE
partition-column-in-key, key-columns-prefix order, AUTO PARTITION (`date_trunc`
+ empty parens), dynamic-partition needs a `PARTITION BY` clause,
`enable_unique_key_partial_update` as a (rejected) table property, and async-MV
`REFRESH` syntax / minimum 1-MINUTE interval / `NOW()` nondeterministic-function rule.

Intentionally **not** L1 cases: claims that are advisory rather than DDL-rejections
(e.g. "don't set `dynamic_partition.buckets`" — Doris does not reject it), and the
runtime-diagnosis / sizing reference rules (those belong to L2/L3). Perf claims
(e.g. prefix-index 36-byte limit effects) need data + measurement, not a DDL probe.

## L2 coverage & finding

`cli/run.sh` seeds a fact+dim dataset, then asserts every command + JSON field that
`../CLI-CONTRACT.md` hard-codes resolves against the live cluster (auto-detecting the
doriscli binary and FE HTTP port). It covers `auth status`, `tablet`, `sql --profile`,
`profile list`, `profile get`, `profile diff`, `profile history`, and `use`
(existence-only — it is state-changing, so it has no JSON contract and is not exercised
in L2's stateless mode; the suite only asserts the command still exists).

Latest run, **Doris 5.0.0 (cloud)** with doriscli post-`dd3f417`: **25 pass, 0 fail.**

### How the suite earned its keep — the `total_scan_rows` gap (doriscli, **not** skills)

On **4.1.1**, `profile get` returned null for `operators[]`, `time_breakdown.plan`,
`scanned_tables`, and `query_stats.total_scan_rows` — one root cause: a `resp.json()`
decode failure on the ~1.2 MB `profile_level=2` profile (`src/connection/http.rs:195`).
On **5.0.0** the first three resolved, leaving `total_scan_rows` null via a *different*
cause — the per-operator `RowsProduced` counter (which `total_scan_rows` is summed
from, `summary.rs:284`) was dropped whenever a `PlanInfo` block preceded it in the
merged profile. The suite marked it `xfail`; doris-cli fixed it in **`dd3f417`** ("keep
per-operator counters when a PlanInfo block precedes them"); re-running here flipped the
marker to `xpass`, confirming the fix, so it is back to a plain `assert`. The `xassert`
(xfail / xpass) mechanism stays in `cli/run.sh` for the next version-specific gap.

## L3 coverage (in progress)

`behavior/run.sh` drives a nested `claude -p` (with `CLAUDECODE` unset) to check the
skills *behave* as written, not just that the prose is correct. The skill text is
injected via `--append-system-prompt` so the behavior under test is this repo's skill,
isolated from any look-alike skill installed globally. The model is non-deterministic,
so bump `SAMPLES` to repeat each case.

Implemented (v1):
- **Evidence-first hard gate** (`cli-investigation.md`): a slow-query prompt with no
  evidence, run with `--disallowedTools Bash` so evidence can't be collected, must
  yield an investigation plan + read-only commands and must **not** propose
  DDL/MV/ALTER fixes. (`SHOW CREATE …` is excluded — it's a read-only evidence command.)

Planned: connection-first rule, the `--profile` safety gate, sizing-as-total-vCPU
(no per-node), brand-neutrality, triggering accuracy (needs a skill-isolated env to
avoid the global look-alike), and the advisor→DDL→loop-back-through-L1 check.

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
