# PASS comment format (`doris-repo-review/v1`)

When a review passes, the skill posts **one comment** on the PR from the locally authenticated
`gh` account. The comment is written by `scripts/post-pass-comment.sh`, never typed by hand: the
agent supplies the numbers and the notes, the script owns the layout. Anything that reads the
comment back — a script, a dashboard, another agent — depends on that layout being fixed.

## Layout

Three layers, each with one job:

| Layer | Content | Consumer |
|---|---|---|
| HTML markers `<!-- doris-repo-review:v1:begin -->` / `:end` | anchor for finding and updating the comment | programs |
| fenced `yaml` block | every structured field | programs (`yaml.safe_load`), and humans |
| markdown body | status heading, `Notes for maintainers`, disclaimer | humans |

````markdown
<!-- doris-repo-review:v1:begin -->
### Local pipeline review — ✅ PASS

```yaml
schema: doris-repo-review/v1
status: PASS
pr: apache/doris#66807
commit: 7f3a91c4e0b25d8a6c1f04b93e27ad5810cf6b42
base: 0b1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f60718293
reviewed_at: 2026-08-17T21:22+08:00
reviewer: morningman
model: claude-opus-5[1m]
effort: max
findings: {blocker: 0, major: 0, minor: 2, nit: 1}
rounds: 2
converged: true
```

**Notes for maintainers**

- `fe/fe-core/src/main/java/org/apache/doris/mysql/authenticate/ldap/LdapManager.java:214` — the
  empty-password fast path is covered by unit tests only; an LDAP regression case is worth adding
  before this is backported to `branch-3.0`.
- The behaviour change is gated by `ldap_authentication_enabled`, so no rolling-upgrade path is
  required.

<sub>Reviewed locally with the `doris-repo-review` pipeline (a local port of
`.github/workflows/code-review-runner.yml`). This is not a CI status check.</sub>
<!-- doris-repo-review:v1:end -->
````

## Fields

| Field | Type | Source |
|---|---|---|
| `schema` | const `doris-repo-review/v1` | the script; bump it if any field changes meaning |
| `status` | `PASS` | the only value ever posted; `CHANGES_REQUESTED` is reserved, not used |
| `pr` | `owner/repo#N` | `meta.env` |
| `commit` | 40-hex | `HEAD_SHA` — the exact commit reviewed |
| `base` | 40-hex | `BASE_SHA` — with `commit` this reproduces the reviewed diff |
| `reviewed_at` | ISO-8601, minute precision, with offset | when the comment was rendered |
| `reviewer` | GitHub login | `gh api user`, falling back to GraphQL `viewer` and `gh auth status` |
| `model` | exact model id | passed with `--model`, e.g. `claude-opus-5[1m]`, `gpt-5.6-sol` |
| `effort` | reasoning effort | `--effort`, default `$CLAUDE_EFFORT` |
| `findings` | inline map | counts per severity; `blocker` and `major` are always 0 in a PASS |
| `rounds` | int | convergence rounds actually run (1-3) |
| `converged` | bool | `false` means the 3-round cap was hit with candidates still open |

Rules the script enforces, so they cannot drift:

- **PASS only.** Any `blocker` or `major` above zero is a `REQUEST_CHANGES` review and the script
  refuses to post — a failing review leaves no trace on GitHub.
- **The PR head must not have moved.** The live `head.sha` is re-read and must equal `commit`,
  otherwise the comment would sign off a commit nobody reviewed.
- **`converged: false` requires at least one note** saying what was left unexamined.
- **At most 5 notes**, each a `- ` bullet (2-space indented continuation lines allowed). Longer
  material belongs in the local review documents.
- **Same commit ⇒ update in place.** An earlier v1 comment by the same account carrying the same
  `commit` is edited via `PATCH`; a different commit gets a new comment, so one push leaves one
  record.
- **Minute precision on `reviewed_at` is deliberate.** A YAML timestamp needs seconds, so
  `2026-08-17T21:22+08:00` stays a plain string in every parser instead of turning into a date
  object in some of them. Do not add seconds.

## Reading it back

```python
import re, yaml, json, subprocess

comments = json.loads(subprocess.check_output(
    ["gh", "api", "repos/apache/doris/issues/66807/comments", "--paginate"]))

for c in comments:
    m = re.search(r"<!-- doris-repo-review:v1:begin -->.*?```yaml\n(.*?)```", c["body"], re.S)
    if not m:
        continue
    d = yaml.safe_load(m.group(1))
    print(d["status"], d["commit"], d["reviewed_at"], d["model"], d["effort"])
    # "has the current head been reviewed and passed?"
    passed = d["status"] == "PASS" and d["commit"] == head_sha
```

`grep`-level check, when a full parse is overkill:

```bash
gh api repos/apache/doris/issues/66807/comments --paginate \
  --jq '.[] | select(.body | test("doris-repo-review:v1:begin")) | .body' \
  | grep -E '^(status|commit|model|reviewed_at):'
```

## Notes for maintainers — what belongs there

The comment is not a substitute for the review documents; it is the receipt. A note earns its
place only when a maintainer would act differently without it:

- a residual risk that did not reach `Minor`, with a `path:line` anchor;
- coverage the review could not reach (no build, no cluster, no test run);
- a backport or upgrade consideration the PR itself does not state;
- with `converged: false`, what was still open when the round cap hit.

Not this: restating what the PR does, listing every `Minor`/`Nit` (they live in the documents),
praise, or anything that reads as an official Apache sign-off. `_None._` is a perfectly good
notes section.
