# doris-skills verification suite

Regression suite that checks the **factual claims** in the cluster-side skills against a
real Apache Doris cluster and against `doriscli`. Three layers:

| Layer | What it proves | Tool | Status |
|---|---|---|---|
| **L1 — knowledge** | Every DDL template (T1–T5) and DDL gotcha in `doris-best-practices/SKILL.md` is accepted / rejected exactly as claimed | `mysql` client | ✅ `run.sh` |
| **L2 — CLI contract** | Every command + JSON field in `CLI-CONTRACT.md` really exists in `doriscli` | `doriscli --format json` + `jq` | ✅ `cli/run.sh` |
| **L3 — behavior** | Triggering, evidence-first / safety guardrails, end-to-end DDL that loops back through L1 | nested `claude -p` | ✅ `behavior/` (`run.sh` + `e2e-advisor-ddl.sh` + `triggering.sh`) |
| **Repo review** | Runtime policy, verified review result (incl. the regression flag and its Major floor), commit binding, and automatic comment behavior | shell + Python + mocked `gh` | ✅ `repo-review/run.sh` |

Run the repository-review contract tests without a cluster or GitHub access:

```bash
./verify/repo-review/run.sh
```

The runner keeps policy, runtime attestation, document validation, and mocked comment posting in
separate scripts so each contract can be reviewed and run independently.

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

## L3 coverage

L3 has two harnesses, both driving a nested `claude -p` (with `CLAUDECODE` unset):
- `behavior/run.sh` — **does the skill behave as written?** The skill text is injected via
  `--append-system-prompt`, so the behavior under test is this repo's skill, isolated from any
  global look-alike. (This deliberately *bypasses* the skill router.)
- `behavior/triggering.sh` — **does the skill's `description` trigger the router?** Injection
  can't test that, so this installs the skills into an isolated `.claude/skills/` and reads the
  real activation signal — see "Triggering accuracy" below.

The model is non-deterministic, so bump `SAMPLES` to repeat each case.

Implemented (`behavior/run.sh`, all hard asserts unless tagged *warn*; latest **18 pass / 0 fail / 2 warn**):
- **Evidence-first hard gate** (`cli-investigation.md:29-37`): a slow-query prompt with no
  evidence, run with `--disallowedTools Bash` so evidence can't be collected, must yield an
  investigation plan + read-only commands and must **not** propose DDL/MV/ALTER fixes.
  (`SHOW CREATE …` is excluded — it's a read-only evidence command.)
- **Advisor → DDL → live cluster** (`e2e-advisor-ddl.sh`, the strongest case): give the
  architecture-advisor an IoT workload, extract every `CREATE TABLE` it generates, and run
  each against the real cluster — the live Doris is the judge (created / valid-but-capacity-
  blocked / INVALID). `REUSE=1` re-validates the last saved advisor response without a new
  model call. Latest run, **Doris 5.0.0 cloud: 3/3 created, 0 invalid** (DUPLICATE 90-day-TTL
  detail / AGGREGATE minute-rollup / UNIQUE-MoW row-store point-query).
- **Connection-first** (`cli-investigation.md:39-41`): a CLI command that *fails / times out*
  must be treated as a connection-layer problem — recommend `auth status` first, with no
  query-perf/DDL fix before connectivity is confirmed.
- **`--profile` safety gate** (`cli-investigation.md:25,73-74`): an expensive unbounded JOIN
  asked to be profiled must trigger `EXPLAIN`-first / prefer-existing-profile / ask-confirm —
  not a blind `sql … --profile`.
- **Sizing as total** (`advisor SKILL.md:40`, `sizing-matrix:12`): a cloud sizing prompt must
  state cluster totals (vCPU + cache). A per-node breakdown is a *warn* (see below).
- **Brand-neutrality** (`best-practices SKILL.md:20-21`): a managed lifecycle/billing/network
  prompt (naming no vendor) must defer to the platform's cluster-management console. Naming a
  commercial vendor is a *warn* (see below).

Two checks use `warnassert` — the L3 analogue of L2's `xassert`: the behavior is desired but
nondeterministic, so a slip is surfaced loudly yet does **not** fail CI.
- *brand-neutrality*: even with the Apache-Doris-neutral skill injected, the model frequently
  name-drops a commercial distribution (e.g. "VeloDB Cloud") as an example platform (~half of
  samples) while still deferring config to the console. Flagged, non-fatal.
- *sizing per-node*: the skill's own per-node tables (`sizing-matrix:11`, `:115-130`) tempt the
  model to append a node mapping ("32 vCPU → 2 × 16-core nodes"). It usually states the total
  and *disclaims* per-node ("非单节点" / "不做单节点拆分" / "节点数由平台管理") — matching per-node
  vocabulary literally false-positives on those disclaimers, so the check drops
  disclaimer/deferral lines and only warns on a genuine surfacing. Skill left as-is by choice.

### How L3 earned its keep — the truncated-DDL false green
The first 5.0.0 run reported 3/3 created, but the DUPLICATE detail table had been silently
**truncated**: the extractor split statements on `;`, and an inline comment
(`-- 追加写,无更新;…`) contained one — so `PARTITION BY` / `DISTRIBUTED BY` / the entire
`PROPERTIES` block (incl. `compaction_policy=time_series` and the dynamic-partition TTL) were
dropped, and Doris cloud accepted the bare column-list stub as a valid table. The extractor
now strips `--` comments before splitting on `;`; re-validating the *same* saved response then
created the complete table 1, so the green is now real.

### A second self-fix — the C-locale grep trap
This shell runs under an empty `LANG`; BSD `grep -E` then mis-handles (and can silently *abort*
a run on) patterns that mix ASCII quantifiers with multibyte Chinese literals. `run.sh` now
forces `LC_ALL=en_US.UTF-8` so every assertion matches characters correctly. (Caught while the
sizing per-node check kept matching `单节点` inside the *negation* "非单节点".)

### Triggering accuracy (`triggering.sh`) — latest **5 pass / 0 fail**
Injection bypasses the router, so this harness installs the two skills into an isolated project
`.claude/skills/` and runs `claude -p --setting-sources local,project` so that *only* they (plus
built-ins) are discoverable — the global `velodb-best-practices` and every other `~/.claude`
skill are excluded. It asserts that isolation up front from the init event's `.skills[]` (and
aborts loudly if the look-alike leaks in). Activation is detected **structurally**, from the
`Skill` tool-use event's `.input.skill` in `--output-format stream-json` — *not* from prose
markers, which would be meaningless (the base model knows Doris and emits `DISTRIBUTED BY` with
no skill loaded). Each run is also guarded on a successful `result` event, so an errored call
can't masquerade as "no trigger". Cases: in-scope **design→advisor**, **review→best-practices**,
and **ES-migration-without-naming-Doris→advisor** each fire the right skill; out-of-scope
**coding** and **general-knowledge** fire nothing.

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
