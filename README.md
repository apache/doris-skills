# Agent Skills for Apache Doris

Agent skills for Apache Doris in the open Agent Skills (`SKILL.md`) format — usable by
Claude Code, Cursor, Codex, Cline, Amp, and other agent tools.

A skill is the decision logic an agent is missing: what evidence to collect, how to read it,
which conclusion it does and does not support. Everything here is **Apache Doris kernel
knowledge** — vendor-neutral, no downstream distribution's branding.

The repository covers two kinds of work:

- **Working with a cluster** — designing tables, sizing, diagnosing production incidents,
  reading query profiles.
- **Working on Doris itself** — contributor workflows against an `apache/doris` source checkout.

Cluster-lifecycle, billing, and networking operations are managed-service specific and
intentionally out of scope; use your platform's cluster-management console for those.

## Skills

Every skill is self-contained — install all of them or only the ones you need. Agents select a
skill from its `description`, so in practice you describe the problem and the right one loads.

### Working with a cluster

| Skill | What it does | Use it when |
|---|---|---|
| [`doris-best-practices`](skills/doris-best-practices/) | Table design, sizing, and runtime query investigation (37 rules, 7 use-case templates, 4 sizing guides) | Writing or reviewing `CREATE TABLE`, choosing a data model, partition/bucket strategy, or cluster configuration |
| [`doris-architecture-advisor`](skills/doris-architecture-advisor/) | Workload-aware architecture design (8 decision rules, 10 worked industry examples) | Turning a business workload into a Doris design — model choice, ingestion strategy, sizing-first planning |
| [`doris-debug`](skills/doris-debug/) | Production diagnostic suite: symptom router + 10 domain skills (query, import, compaction, node, MV, tablet, deployment, data-lake, resource-isolation, cloud), 16 case files, 45 case patterns | Something is broken — slow queries, failing imports, `-235` compaction errors, OOM or crashing nodes, an MV that will not rewrite, degraded tablets |
| [`doris-profile-reader`](skills/doris-profile-reader/) | Query runtime profile interpretation and bottleneck triage (counter semantics, join-order / runtime-filter diagnosis, 9 reference guides) | You have a profile, query id, or profile URL and need to know what actually made the query slow |

### Working on Doris itself

The three follow a change from its first line to its merge: `develop-with-evidence` while it is
written, `doris-pr-description` when it is opened as a PR, and `doris-repo-review` when it is
reviewed. The first two connect through a handoff file that development leaves under
`.git/pr-handoff/`, so the PR description is written from the evidence gathered while the code
was written instead of being reconstructed from the diff. Each one also works on its own.

| Skill | What it does | Use it when |
|---|---|---|
| [`develop-with-evidence`](skills/develop-with-evidence/) | Six-stage development workflow (scope → implement → verify → self-review → evidence → deliver): confirms that a reported bug is real before fixing it, picks verification in proportion to the change type (11 change types, from bugfix to data migration), checks that the tests can tell right from wrong (fail on the baseline, pass on the candidate, a targeted revert when a false pass is suspected), keeps every evidence entry bound to the final code, and leaves an English handoff file: a PR description draft, the decisions and their alternatives, the evidence, and a `Ready` / `Partially verified` / `Not ready` pre-submission status. It never publishes the PR | Implementing a feature, fixing a bug, refactoring, optimizing, or changing tests, CI, configs, or dependencies in an `apache/doris` checkout (the workflow itself is repository-agnostic) |
| [`doris-pr-description`](skills/doris-pr-description/) | PR title and description by the Doris PR standard: Create, Update, Rewrite, and Check modes; 10 PR types, each with its required fields and a worked example; a Background-first template, a Change map for large diffs, and an issue draft for a Feature that has none; a bundled structural checker (`check_pr.py`) and diff profiler (`diff_profile.py`). Takes the facts from the `develop-with-evidence` handoff file when there is one, and pushes, creates, or edits on GitHub only after the user confirms the drafts | Opening or updating an `apache/doris` PR, or rewriting or checking the title and description of an existing one |
| [`doris-repo-review`](skills/doris-repo-review/) | Contributor-side PR review of a local `apache/doris` clone, running the same flow as the CI Code Review Runner: worktree alignment, risk scan with premise checks, subagent fan-out, shared ledger, mechanical coverage report, anchored EN + ZH review documents kept per reviewed head with a per-finding category and a regression flag judged against the merge base that floors an undeclared functional / data / resource / performance change at Major, dismissals carried forward from earlier reviews of the same PR, and — on a passing review — one machine-readable PASS comment on the PR that discloses any remaining behaviour change | Reviewing an `apache/doris` pull request locally, the way the pipeline would |

These skills work in a Doris **source** checkout, not against a running cluster (only
`develop-with-evidence` may start a local one, to reproduce a bug or run tests); the cluster-side
skills never touch repository source. `develop-with-evidence` is the one skill that edits code,
builds, and runs tests, and it does so only to implement the change and gather evidence.
`doris-repo-review` is read-only: no edits to source, no build, no tests. GitHub writes come from
two places:

- `doris-pr-description` pushes the branch and creates or edits the PR (and the issue a Feature
  needs) only after the user confirms the drafts, unless the request itself said to publish
  without review. Its Rewrite and Check modes never write to GitHub.
- `doris-repo-review` posts its PASS comment only when the review finds no `Blocker` or `Major`,
  converges under a qualified reviewer, and still matches the live PR head. Explicitly invoking
  the skill authorizes that one automatic comment.

## Install

The open [`skills`](https://github.com/vercel-labs/skills) CLI works across agent tools
(Claude Code, Cursor, Codex, Cline, Amp, …), auto-discovers every skill in this repository, and
bundles their `references/` and `scripts/`:

```bash
npx skills add apache/doris-skills
```

Or copy them in manually:

```bash
cp -r skills/* ~/.claude/skills/          # all of them
cp -r skills/doris-debug ~/.claude/skills/   # or just one
```

Then describe your problem — the agent loads the matching skill on its own:

| You say | What loads |
|---|---|
| "Design tables for a 2 TB/day clickstream workload" | `doris-architecture-advisor` → `doris-best-practices` |
| "Review this DDL before I ship it" | `doris-best-practices` |
| "Imports keep failing with -235" | `doris-debug` → its compaction domain skill |
| "Why is this query slow? here's the profile" | `doris-profile-reader` |
| "Fix this bug and open a PR for it" | `develop-with-evidence` → `doris-pr-description` |
| "Does the description of https://github.com/apache/doris/pull/66807 meet the PR standard?" | `doris-pr-description` |
| "/doris-repo-review https://github.com/apache/doris/pull/66807" | `doris-repo-review` |

### Optional: doriscli

The cluster-side skills pair with **`doriscli`**, the Apache Doris CLI (companion
[`doris-cli`](https://github.com/apache/doris-cli) repository). doriscli is the "hands" — it runs
SQL, fetches and parses query profiles, and analyzes tablet distribution, all as structured JSON;
the skills are the "brain" — the decision logic that reads that JSON and recommends table
designs, sizing, and fixes.

The recommended install is from **npm**, which ships prebuilt binaries (no Rust toolchain, no
compile step):

```bash
npm install -g @apache-doris/doriscli
doriscli --version
```

For other platforms, or to build from source, see the
[`doris-cli`](https://github.com/apache/doris-cli) repository.

doriscli is optional: without it the skills fall back automatically to plain MySQL-protocol SQL
plus the FE HTTP API (see
[`cli-investigation.md`](skills/doris-best-practices/references/cli-investigation.md)). The exact
commands and JSON fields the skills depend on are listed in [CLI-CONTRACT.md](CLI-CONTRACT.md) —
keep that file and doriscli in sync.

The contributor-side skills do not use doriscli. `doris-repo-review` needs `git`, an
authenticated `gh` CLI, `jq`, and `python3`; `doris-pr-description` needs `git` and `python3`,
plus an authenticated `gh` CLI to read or publish PRs and issues; `develop-with-evidence` needs
`git` and whatever the project itself uses to build and test.

## Verification

The factual claims in the cluster-side skills are regression-tested — against a real Apache Doris
cluster, against `doriscli`, and against the skills' own runtime behavior — so they do not drift
from reality. See [`verify/`](verify/README.md); it runs three cluster/behavior layers plus a
repository-review contract suite:

- **L1 — knowledge**: every DDL template and gotcha in `doris-best-practices` is accepted
  or rejected by a live cluster exactly as the skill claims (`mysql` client).
- **L2 — CLI contract**: every command and JSON field in [CLI-CONTRACT.md](CLI-CONTRACT.md)
  really resolves against `doriscli` on a live cluster (`doriscli --format json` + `jq`).
- **L3 — behavior**: the skills *behave* as written — evidence-first and safety guardrails,
  an end-to-end advisor→DDL→live-cluster loopback, and skill-router triggering — exercised
  through a nested `claude -p`.
- **Repo review**: qualified-runtime policy, document-result validation, and mocked GitHub comment
  create/update behavior.

A skill that makes no DDL or doriscli claim (`doris-debug`, `doris-profile-reader`, and the
contributor-side skills) has no L1/L2 coverage. `doris-repo-review`'s local receipt contract is
covered by the repo-review suite, and `doris-pr-description` ships a self-test that runs its
checker over every worked example and confirms that each type file documents the fields the
checker requires:

```bash
python3 skills/doris-pr-description/scripts/check_pr.py --self-test
```

## Contributing a skill

A skill is one directory under `skills/`:

```
skills/<skill-name>/
├── SKILL.md          # required — frontmatter + the workflow the agent follows
├── references/       # optional — depth the agent loads on demand
├── scripts/          # optional — deterministic work better done in code than by the model
└── <domain>/         # optional — nested sub-skills, each with its own SKILL.md (see doris-debug)
```

`SKILL.md` starts with `name` and `description` frontmatter. The `description` is the only thing
the router sees, so it must state **what the skill does and when to reach for it**, in the words a
user would actually type. Keep `SKILL.md` itself to the decision logic and push depth into
`references/` — the agent reads those on demand.

Rules:

- Write `doriscli` and `Apache Doris` directly. **Never** introduce a downstream distribution's
  brand strings — CLI names, console URLs, env-var prefixes, hostnames.
- Cloud-mode behavior (storage-compute separation, `replication_num=1`, file cache) is
  **Doris kernel architecture** — describe it neutrally as "cloud mode" / "storage-compute".
  Managed-service behavior (suspend/resume, automatic node-count management, billing) is
  out of scope; point at the user's cluster-management console rather than naming a product.
- If you rely on a new doriscli command or output field, add it to
  [CLI-CONTRACT.md](CLI-CONTRACT.md) so the two repositories stay in sync.
- Add a row to the matching table above so the skill is discoverable from this README.

## Layout

```
doris-skills/
├── README.md
├── CLI-CONTRACT.md                 # doriscli commands + JSON fields the skills depend on
├── skills/
│   ├── doris-best-practices/       # cluster-side: table design, sizing, query investigation
│   ├── doris-architecture-advisor/ # cluster-side: workload → architecture
│   ├── doris-debug/                # cluster-side: symptom router + 10 nested domain skills
│   ├── doris-profile-reader/       # cluster-side: query profile → bottleneck
│   ├── develop-with-evidence/      # contributor-side: develops a change with evidence, leaves a PR handoff
│   ├── doris-pr-description/       # contributor-side: writes and checks a PR's title and description
│   └── doris-repo-review/          # contributor-side: reviews an apache/doris PR, not a cluster
└── verify/                         # regression suite — L1 DDL, L2 CLI contract, L3 behavior
```

## License

Apache-2.0
