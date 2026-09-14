# Review document templates

Two documents, same content, same finding IDs, same order, named by the head that was reviewed:

- `review-docs/pr-<N>-review.<head7>.en.md`
- `review-docs/pr-<N>-review.<head7>.zh.md`
- `review-docs/pr-<N>-review.en.md` / `.zh.md` — symlinks to the newest pair

When the branch has no PR, use `review-docs/<branch-slug>-review.<head7>.en.md` / `.zh.md`.

**Never overwrite an earlier run's pair.** `review-docs/` is untracked, so overwriting is
permanent, and what it destroys is the only record of what an earlier review already considered
and dismissed. Re-running against the *same* head overwrites that head's pair, and only that one.

The ZH document is a real Chinese review, not a machine translation of the EN one: same facts,
same anchors, same IDs, same severities, categories and regression flags, but idiomatic Chinese.
Identifiers, file paths, log messages, config names, code snippets, and the severity words
(`Blocker` / `Major` / `Minor` / `Nit`) stay in their original form in both documents.

## Anchor format (mandatory, both documents)

Local review has no inline comments, so an anchor is the only way a reader finds the code.

- Write anchors inside backticks: `` `fe/fe-core/src/main/java/org/apache/doris/X.java:412` ``
  or `` `path:412-430` ``. `scripts/verify-review-docs.py` only recognises this form.
- Numbers are NEW-SIDE (post-change) line numbers of the worktree at HEAD, cross-checked
  against `changed_line_ranges.txt` and confirmed by reading the file.
- Every finding carries at least one anchor plus a fenced snippet copied verbatim from it.
- Pure deletion: anchor the surviving seam line and add `(deleted, base line N)`.
- Missing thing (no test / no metric / no compat path): anchor the most relevant existing line
  and state what should be there.
- Anchors inside fenced code blocks are ignored by the verifier — never hide a real anchor there.

## Verdict rule

| Highest severity present | Verdict |
|---|---|
| `Blocker` or `Major` | `REQUEST_CHANGES` |
| only `Minor` / `Nit` / none | `APPROVE` |

The verdict is about severity; **convergence is a separate statement and must not be confused with
it.** A round converges when it produced no new `Blocker`/`Major` *and* the coverage report is
clean (SKILL.md step 7). A run that ended with Minor and Nit findings still arriving **converged**
— report it as such, and name the round after which the verdict stopped moving. Only report "did
not converge" when blocking findings were still appearing at the cap, or when changed files
remained unread; say which of the two it was.

Severity meanings: `Blocker` = correctness, data loss, deadlock, crash, incompatible change
without a compat path, or a broken build/test contract. `Major` = real defect or a missing
guarantee that will bite in production or during upgrade. `Minor` = worth fixing, not urgent.
`Nit` = style or wording.

## Category, regression flag, and severity floors

Every finding carries two more mandatory lines right after its severity — its **category** and
whether it is a **regression**:

```markdown
- **Category**: functional-loss (lifecycle)        <!-- EN;  ZH: - **类别**：功能缺失（生命周期） -->
- **Regression**: yes                              <!-- EN;  ZH: - **回归**：是 / 否 -->
```

### Category

The category names the *consequence* of the finding, from this closed vocabulary. The
verifier rejects any other value, so an unrecognised category cannot slip past the floor. One
class per finding; the domain that produced it (concurrency, lifecycle, compatibility, config,
…) goes in an optional parenthetical after the class.

| Category (EN / ZH) | What belongs here | Regression floor |
|---|---|---|
| `functional-bug` / `功能缺陷` | the code does the wrong thing: crash, exception, hang, deadlock, wrong branch, wrong control flow, a check that fires when it should not | at least `Major` |
| `functional-loss` / `功能缺失` | something the base did, or the PR claims, no longer happens: a dropped reset, a removed compat path, a check that no longer runs, a sibling path left unchanged, a rolling-upgrade path that breaks | at least `Major` |
| `data-error` / `数据错误` | wrong query results, lost, duplicated or corrupted data, an edit log or persisted state that does not replay | at least `Major` |
| `resource-leak` / `资源泄露` | memory, file descriptors, threads, connections, locks, temp files, tablets or statements not released | at least `Major` |
| `performance` / `性能降低` | slower, more memory / CPU / IO, a lost optimisation, an unbounded loop or allocation | at least `Major` |
| `observability` / `可观测性` | logs, VLOG, metrics, profile fields, the diagnostic content of an error message | judged normally |
| `test-coverage` / `测试覆盖` | missing, weakened, or non-negative tests; a gate a change would leave green | judged normally |
| `wording` / `措辞` | comments, docs, messages, naming | judged normally |
| `maintainability` / `可维护性` | duplication, dead code, structure, an unexplained special case | judged normally |

Spelling is compared case-insensitively with spaces, hyphens and underscores removed, and the
ZH forms `功能性bug` / `功能性缺失` / `资源泄漏` / `性能` are accepted as aliases. EN and ZH
documents must agree on the category of every finding.

### Regression

`yes` means the behaviour at HEAD differs from the **merge base** in a way the PR body does not
declare as intended — the cell of the differential table that the author did not ask for. `no`
means the defect was already there (the PR merely exposes, documents, or moves it) or the change
is the one the PR set out to make. The evidence is `git show <MERGE_BASE>:<path>`; name it in
the finding.

The comparison point is `MERGE_BASE` (from `meta.env`), **not** `BASE_SHA`. `BASE_SHA` is the
tip of the target branch — the snapshot the diff was cut against and the commit the PASS receipt
binds to — and it may carry commits the PR branch has never seen (`TARGET_AHEAD` in `meta.env`
counts them). A fix that landed on the target branch after the PR branched off is absent at
HEAD without the PR having removed anything, and a normal merge keeps it; comparing against
`BASE_SHA` would report it as a "dropped" behaviour and a Major regression that does not exist.
Whether the PR still merges cleanly *semantically* against a target branch that has moved on is
a real question, but a different one — raise it, when it applies, as its own finding or
dismissal row, never as `Regression: yes`.

`verify-review-docs.py` rejects a finding without the line and rejects EN/ZH documents whose
flags disagree.

### Floors

The flag and the category together drive a floor that the verifier enforces and that no
amount of "but it is narrow" overrides:

| Condition | Floor |
|---|---|
| `Regression: yes` in `functional-bug`, `functional-loss`, `data-error`, `resource-leak`, or `performance` | at least `Major` — the verifier rejects `Minor` / `Nit` |
| `Regression: yes` in `observability`, `test-coverage`, `wording`, or `maintainability` | judged normally by consequence; below `Major` the finding **must** carry a **Severity rationale** paragraph saying why the behaviour change is acceptable (the verifier checks that it is there), and the PASS receipt must name it in its notes |
| a PR presented as behaviour-preserving (`[refactor]`, `[chore]`, "Behavior changed: No", or any wording that claims equivalence): **every** differing cell of the D1 differential table that the PR body does not name as intended | `Regression: yes`, classified by its consequence like any other finding — a cell that differs in what the code *does* (as opposed to what it logs or says) is `functional-loss` / `functional-bug` / `data-error`, hence at least `Major`. The reviewer's job is to find the cell and name its consequence, not to decide whether it matters |

Severity is the consequence *when* the finding triggers — what is wrong, leaked, lost, or
silently skipped — never the probability that it triggers. A narrow trigger (one protocol, cloud
only, a retry that has to fail twice), a rare environment, or a one-line fix is not a discount. The
review of apache/doris#67900 rated a per-attempt reset that the PR had dropped as `Minor` because
the trigger was "Flight + replan + failing retry" and the fix was one line; the connector statement
scope it leaked was raised again by the next reviewer as a must-fix. Under this table that finding
is `functional-loss` (the reset the base performed no longer happens), `Regression: yes`, and
therefore at least `Major` — the case this section exists to prevent.

**Downgrading needs a written rationale.** When the main agent rates a candidate below what the
subagent proposed, or dismisses a `functional-bug` / `functional-loss` / `data-error` /
`resource-leak` candidate, the finding (or the "Considered and Dismissed" row) must carry a
**Severity rationale** paragraph: the consequence analysis — what happens when it triggers, who
notices, what is left leaked or wrong — and explicitly why that is not `Major`. "Narrow",
"one-line fix", or "no wrong result" alone is not a rationale. SKILL.md step 6 additionally
dispatches a severity-challenge subagent before such a downgrade is final.

---

## English template

```markdown
# Code Review — PR #<N>: <title>

| | |
|---|---|
| PR | <url> (state: <open/merged/closed>) |
| PR head | `<PR_HEAD_SHA>` on `<PR_HEAD_REF>` of `<PR_HEAD_REPO>` |
| Diff range | `<BASE_SHA>...<HEAD_SHA>` (three-dot, merge base `<MERGE_BASE>`) |
| Scope | <n> files, +<a>/-<b> lines, <c> commits |
| Reviewed in | `<WORKDIR>` (<ALIGN_MODE>), on <YYYY-MM-DD> |
| Local alignment | branch check: <…>; commit check: <same / ahead:N / behind:N / diverged:a/b> |
| Verdict | **REQUEST_CHANGES** / **APPROVE** |
| Rounds | <r> of max 3; converged (verdict stable since round <n>) / did not converge (<which condition failed>) |
| Builds on | <prior heads reviewed, from prior_runs/, or "first review of this PR"> |

<!-- Only when commit check was ahead:N before aligning: -->
> `<N>` local commit(s) on `<branch>` are ahead of the PR head and are **not** covered by
> this review.

## Summary

<3-8 sentences: what the PR does, whether it achieves it, and the headline concerns.>

## Findings

<Ordered by severity, then by file. Omit the section entirely if there are none.>

### F-01 · <one-line title>

- **Severity**: Blocker
- **Category**: functional-bug (concurrency) <!-- one of functional-bug / functional-loss / data-error / resource-leak / performance / observability / test-coverage / wording / maintainability; the domain goes in the parenthesis. Mandatory. -->
- **Regression**: yes <!-- yes = behaviour differs from the merge base and the PR body does not declare it intended; no = pre-existing or intended. Mandatory; yes in the first five categories is at least Major. -->
- **Where**: `path/to/File.java:412-430`

```java
<verbatim snippet from the anchor>
```

**What is wrong.** <the defect, stated once>

**Why it happens.** <call chain with `path:line` citations, the invariant that breaks>

**When it bites.** <a concrete trigger scenario — who calls what, in which order, with which data>

**Severity rationale.** <required whenever the severity is below what a subagent proposed, a
regression is rated at the floor rather than Blocker, or a regression in observability /
test-coverage / wording / maintainability is rated below Major (say why the behaviour change is
acceptable): the consequence when it triggers and why that is (not) worse. Omit for findings rated
as proposed.>

**Suggested fix.**

```diff
<a precise patch when the fix is small and self-contained; prose only when it is architectural>
```

## Critical Checkpoints

<Part 1.3 of the repo code-review skill requires an individual conclusion per applicable item.
One row per checkpoint. Mark non-applicable items `n/a` with a half-line reason — do not drop them.>

| Checkpoint | Conclusion |
|---|---|
| Goal achieved, proven by a test | <conclusion, with `path:line` where relevant> |
| Change is minimal, clear, focused | |
| Concurrency: threads, shared state, locks, lock order | |
| Lifecycle / static init order | |
| New config: dynamic? observed without restart? | |
| Incompatible change: rolling-upgrade path | |
| Parallel code paths updated | |
| Special conditionals explained | |
| Test coverage (e2e, negative, unit) | |
| Test results added/modified and correct | |
| Observability (logs, VLOG, metrics) | |
| Transaction / persistence / EditLog replay | |
| Data write atomicity, crash safety | |
| New FE↔BE variables on every send path | |
| Performance and anti-patterns | |
| Anything else | |

## Response to Review Focus

<Answer each user focus point from review_focus.txt, including "no additional issue found for
this point". Write "No additional user-provided review focus." when there was none.>

## Considered and Dismissed

<Every suspicious point that did NOT become a finding, with the code evidence that rules it
out. This is what makes the review auditable — do not silently drop a concern.>

| # | Concern | Where | Why it is not an issue |
|---|---|---|---|
| D-01 | | `path:line` | |

## Coverage and Limits

- Files reviewed in depth: <...>
- Files skimmed and why: <...>
- Subagents: <round/id/coverage table>
- Not verified locally: <builds, tests, and anything that needs a running cluster>
- Evidence taken from outside the repository: <dependency artifacts opened, with versions, or "none">
- Inherited from earlier runs: <heads, and how many dismissals were carried forward — or "first review of this PR">
- Convergence: <converged, verdict stable since round N / did not converge because <condition>>
- Uncommitted worktree paths excluded from this review: <from worktree_status.txt, or "none">
```

---

## Chinese template

```markdown
# 代码评审 — PR #<N>：<标题>

| | |
|---|---|
| PR | <url>（状态：<open/merged/closed>） |
| PR head | `<PR_HEAD_SHA>`，来自 `<PR_HEAD_REPO>` 的 `<PR_HEAD_REF>` |
| Diff 范围 | `<BASE_SHA>...<HEAD_SHA>`（三点，merge base `<MERGE_BASE>`） |
| 规模 | <n> 个文件，+<a>/-<b> 行，<c> 个 commit |
| 评审位置 | `<WORKDIR>`（<ALIGN_MODE>），<YYYY-MM-DD> |
| 本地一致性 | 分支：<…>；commit：<一致 / 领先 N / 落后 N / 已分叉 a/b> |
| 结论 | **REQUEST_CHANGES** / **APPROVE** |
| 轮次 | 共 <r> 轮（上限 3）；已收敛（结论自第 <n> 轮起稳定）/ 未收敛（哪个条件没满足） |
| 承接自 | <prior_runs/ 里更早评审过的 head，若没有则写"本 PR 的首次评审"> |

<!-- 仅当对齐前 commit check 是领先 N 时保留： -->
> `<branch>` 上有 `<N>` 个本地提交领先于 PR head，**不在**本次评审范围内。

## 总体结论

<3-8 句：这个 PR 做了什么、有没有做到、最主要的问题是什么。>

## 问题清单

### F-01 · <一句话标题>

- **等级**：Blocker
- **类别**：功能缺陷（并发） <!-- 功能缺陷 / 功能缺失 / 数据错误 / 资源泄露 / 性能降低 / 可观测性 / 测试覆盖 / 措辞 / 可维护性 之一；所属领域写在括号里。必填。 -->
- **回归**：是 <!-- 是 = HEAD 的行为与 merge base 不同且 PR 描述没有声明这是有意的；否 = 既有问题或有意改动。必填；前五类里的回归至少是 Major。 -->
- **位置**：`path/to/File.java:412-430`

```java
<锚点处原样摘录的代码>
```

**问题是什么。** <一句话把缺陷说清楚>

**为什么会这样。** <调用链，带 `path:line` 引用，说明被破坏的不变式>

**什么时候会踩到。** <具体触发场景：谁在什么顺序上调用了什么、数据长什么样>

**定级理由。** <当等级低于子 agent 提议、回归只定在 Major 下限而非 Blocker、或可观测性 / 测试覆盖 / 措辞 / 可维护性类的回归定在 Major 以下（说明为什么这个行为变化可以接受）时必填：触发后的后果是什么、为什么（不）更严重。等级与提议一致时可省略。>

**修改建议。**

```diff
<小而自洽的改动给出精确 patch；架构性问题只用文字说明>
```

## 关键检查项

| 检查项 | 结论 |
|---|---|
| 目标是否达成、是否有测试证明 | <结论，必要时带 `path:line`> |
| 改动是否足够小、清晰、聚焦 | |
| 并发：线程、共享变量、锁与锁序 | |
| 生命周期 / 静态初始化顺序 | |
| 新增配置：是否该动态、是否真能动态生效 | |
| 不兼容改动：滚动升级路径 | |
| 平行代码路径是否同步修改 | |
| 特殊条件判断是否有注释说明 | |
| 测试覆盖（e2e、负例、单测） | |
| 测试结果是否补充/更新且正确 | |
| 可观测性（日志、VLOG、Metrics） | |
| 事务 / 持久化 / EditLog 回放 | |
| 数据写入原子性与崩溃安全 | |
| 新增 FE↔BE 变量的所有传递路径 | |
| 性能与反模式 | |
| 其它 | |

## 对关注点的回应

<逐条回应 review_focus.txt 中用户提出的关注点，没发现问题也要明确说明。用户没提的话写“用户未指定额外关注点”。>

## 已排查并排除的疑点

| # | 疑点 | 位置 | 为什么不是问题 |
|---|---|---|---|
| D-01 | | `path:line` | |

## 覆盖范围与局限

- 深入看过的文件：<...>
- 只扫了一眼的文件及原因：<...>
- 子 agent 分工：<轮次 / id / 覆盖面 表格>
- 本地未验证：<编译、用例，以及任何需要真实集群才能确认的部分>
- 仓库之外取到的证据：<打开过的依赖产物及版本，没有就写“无”>
- 承接自更早的评审：<更早的 head，以及沿用了多少条已排除结论——首次评审就写“本 PR 的首次评审”>
- 收敛情况：<已收敛，结论自第 N 轮起稳定 / 未收敛，因为 <哪个条件>>
- 未纳入本次评审的未提交改动：<取自 worktree_status.txt，没有就写“无”>
```
