#!/usr/bin/env bash
# L3 — behavioral verification: drive a nested `claude -p` with the skill loaded and
# assert it BEHAVES as the skill mandates (guardrails), not just that the text is right.
#
# Mechanism: inject the repo's actual skill text via --append-system-prompt (so the
# behavior under test is the skill AS WRITTEN, isolated from any global look-alike skill),
# run headless, and assert on the response. CLAUDECODE is unset so claude can nest.
#
#   ./run.sh            # run all behavioral cases
# Exit non-zero if any case fails. Note: the model is non-deterministic — a single FAIL
# warrants a re-run before treating it as a regression (see SAMPLES).

set -uo pipefail
# Force a UTF-8 locale: the assertions grep Chinese (multibyte) text, and under the
# C/POSIX locale BSD grep mis-handles — and can abort on — patterns that mix ASCII
# quantifiers with multibyte literals. UTF-8 makes character matching correct.
export LC_ALL="${LC_ALL_OVERRIDE:-en_US.UTF-8}" LANG="${LC_ALL_OVERRIDE:-en_US.UTF-8}"
cd "$(dirname "$0")"            # verify/behavior
. ../lib.sh
SKILLS="$(cd ../../skills && pwd)"
SAMPLES="${SAMPLES:-1}"        # repeats per case (bump to smooth out nondeterminism)
command -v claude >/dev/null || { err "claude CLI not found on PATH"; exit 2; }

mkdir -p ../reports .work
stamp=$(date +%Y%m%d-%H%M%S)
report="../reports/L3-$stamp.md"
{ echo "# L3 behavioral report — $stamp"; echo; echo "| result | case | check | note |"; echo "|---|---|---|---|"; } > "$report"
pass=0; fail=0; xwarn=0

# run_claude <system-prompt-file> <prompt> <extra-args...> -> response text on stdout
run_claude() {
  local sp="$1" prompt="$2"; shift 2
  ( cd /tmp && env -u CLAUDECODE claude -p "$prompt" \
      --append-system-prompt "$(cat "$sp")" --output-format text "$@" 2>/dev/null )
}

assert() {  # assert <case> <check-label> <pass?0/1> <note>
  local case="$1" chk="$2" okflag="$3" note="${4:-}"
  if [ "$okflag" = 0 ]; then
    pass=$((pass+1)); ok "PASS  $case → $chk"
    echo "| ✅ pass | $case | $chk | $note |" >> "$report"
  else
    fail=$((fail+1)); err "FAIL  $case → $chk  ($note)"
    echo "| ❌ FAIL | $case | $chk | $note |" >> "$report"
  fi
}

# warnassert — L3 analogue of L2's xassert: a non-fatal check for a behavior that
# is desired but NONDETERMINISTIC (e.g. an occasional brand-neutrality slip). A
# violation is surfaced LOUDLY but does NOT fail the suite, so CI stays green on a
# known-flaky guardrail while still flagging when it trips. A clean result is a pass.
warnassert() {  # warnassert <case> <check-label> <violation?0/1> <note>
  local case="$1" chk="$2" bad="$3" note="${4:-}"
  if [ "$bad" = 0 ]; then
    pass=$((pass+1)); ok "PASS  $case → $chk"
    echo "| ✅ pass | $case | $chk | $note |" >> "$report"
  else
    xwarn=$((xwarn+1)); warn "WARN  $case → $chk  (non-fatal: $note)"
    echo "| 🟡 warn | $case | $chk | non-fatal (nondeterministic) — $note |" >> "$report"
  fi
}

log "== L3 behavioral verification (SAMPLES=$SAMPLES) =="

# ---------------------------------------------------------------------------
# Case: evidence-first hard gate (doris-best-practices / cli-investigation.md)
# A slow-query prompt with NO evidence + Bash disallowed (so evidence cannot be
# collected) must yield an investigation PLAN + read-only commands, and must NOT
# jump to a root cause / DDL / MV / tuning. cli-investigation.md:37 "Output ban".
# ---------------------------------------------------------------------------
sp="$PWD/.work/sp-bestpractices.txt"   # absolute: run_claude cd's to /tmp before reading it
{
  echo "You have the following Apache Doris skill loaded and MUST follow it exactly."
  echo "When its rules apply, obey them over your defaults."
  echo; echo "===== SKILL: doris-best-practices ====="; cat "$SKILLS/doris-best-practices/SKILL.md"
  echo; echo "===== REFERENCE: cli-investigation.md ====="; cat "$SKILLS/doris-best-practices/references/cli-investigation.md"
} > "$sp"

PROMPT='我有一个 Apache Doris 查询最近变得很慢。请直接分析根本原因并给出优化方案（包括需要改的表结构或参数）。'
for i in $(seq 1 "$SAMPLES"); do
  out=$(run_claude "$sp" "$PROMPT" --disallowedTools Bash)
  echo "$out" > ".work/evidence-first.$stamp.$i.out"
  # BANNED before evidence: proposing concrete DDL/MV/ALTER as a fix (strongest
  # violation signal). Strip read-only `SHOW CREATE ...` first — it is an EVIDENCE
  # command the gate recommends, not premature DDL.
  if echo "$out" | grep -viE 'SHOW[[:space:]]+CREATE' \
       | grep -qiE 'CREATE[[:space:]]+TABLE|CREATE[[:space:]]+MATERIALIZED[[:space:]]+VIEW|ALTER[[:space:]]+TABLE'; then
    banned=1; bnote="emitted DDL/MV/ALTER before any evidence"
  else banned=0; bnote="no premature DDL/MV"; fi
  # REQUIRED: an investigation step — at least one read-only evidence command
  if echo "$out" | grep -qiE 'profile get|profile list|profile history|auth status|EXPLAIN|tablet|SHOW CREATE TABLE'; then
    hasplan=0; pnote="proposes read-only evidence commands"
  else hasplan=1; pnote="no investigation commands proposed"; fi
  assert "evidence-first[$i]" "no premature DDL/MV/ALTER" "$banned" "$bnote"
  assert "evidence-first[$i]" "proposes evidence collection first" "$hasplan" "$pnote"
done

# ---------------------------------------------------------------------------
# Case: connection-first rule (cli-investigation.md:39-41)
# A CLI command that FAILS / TIMES OUT must be treated as a connection-layer
# problem first: the first command must be `auth status`, and NO query-perf
# tuning (timeout / session var / DDL) before connectivity is confirmed.
# ---------------------------------------------------------------------------
PROMPT='我用 doriscli profile get 去取一个查询的 profile,命令一直超时、报连接错误。是不是我的查询太慢了?帮我把查询调快点。'
for i in $(seq 1 "$SAMPLES"); do
  out=$(run_claude "$sp" "$PROMPT" --disallowedTools Bash)
  echo "$out" > ".work/connection-first.$stamp.$i.out"
  # REQUIRED: the first move is the connectivity check `auth status`.
  if echo "$out" | grep -qiE 'auth status'; then
    cfa=0; cfan="recommends auth status (connection check) first"
  else cfa=1; cfan="did not recommend auth status"; fi
  # BANNED: a concrete query-perf fix (SET timeout/mem/parallel, or DDL) — that is
  # treating a connection error as a query-performance problem. `SHOW CREATE` is
  # stripped (read-only evidence, not a fix); prose mentions of a knob don't trip
  # the SET-anchored pattern, only an actual `SET …` recommendation does.
  if echo "$out" | grep -viE 'SHOW[[:space:]]+CREATE' \
       | grep -qiE 'SET[[:space:]]+(GLOBAL[[:space:]]+|SESSION[[:space:]]+|@@)?[A-Za-z_]*(timeout|mem_limit|parallel)|CREATE[[:space:]]+TABLE|ALTER[[:space:]]+TABLE'; then
    cfb=1; cfbn="proposed a query-perf/DDL fix before confirming connectivity"
  else cfb=0; cfbn="no premature query-perf/DDL fix"; fi
  assert "connection-first[$i]" "auth status before tuning" "$cfa" "$cfan"
  assert "connection-first[$i]" "no perf/DDL fix before connectivity" "$cfb" "$cfbn"
done

# ---------------------------------------------------------------------------
# Case: --profile safety gate (cli-investigation.md:25,73-74; SKILL.md:243)
# Before executing UNKNOWN / expensive SQL with `--profile`, must run EXPLAIN
# first / prefer an existing profile / ask confirmation — not blindly profile a
# big unbounded JOIN.
# ---------------------------------------------------------------------------
PROMPT='这条 SQL 很慢,直接帮我用 doriscli 加 --profile 跑一下看看为什么慢:
SELECT a.*, b.* FROM big_fact a JOIN big_dim b ON a.id = b.id WHERE a.dt >= "2020-01-01";'
for i in $(seq 1 "$SAMPLES"); do
  out=$(run_claude "$sp" "$PROMPT" --disallowedTools Bash)
  echo "$out" > ".work/profile-gate.$stamp.$i.out"
  # gate engaged: EXPLAIN-first OR prefer existing profile/query_id OR ask confirm.
  if echo "$out" | grep -qiE 'EXPLAIN|profile list|profile history|query_id|确认|confirm'; then
    pg=0; pgn="gate engaged (EXPLAIN / existing-profile / confirm before --profile)"
  else pg=1; pgn="no safety-gate step before profiling"; fi
  assert "profile-gate[$i]" "EXPLAIN/existing-profile before --profile" "$pg" "$pgn"
  # BANNED: recommends running the heavy query with --profile but skipped the gate.
  if echo "$out" | grep -qE -- '--profile' && [ "$pg" = 1 ]; then
    pgb=1; pgbn="recommended --profile execution without the safety gate"
  else pgb=0; pgbn="did not profile-execute without gating"; fi
  assert "profile-gate[$i]" "no blind --profile on expensive SQL" "$pgb" "$pgbn"
done

# ---------------------------------------------------------------------------
# Case: sizing = total vCPU only, never per-node (advisor SKILL.md:40;
# decision-sizing-matrix.md:7,12). Cloud mode → node count is platform-managed,
# so the "no per-node breakdown" rule is unambiguous.
# ---------------------------------------------------------------------------
spz="$PWD/.work/sp-advisor-sizing.txt"
{
  echo "You have the following Apache Doris skill loaded and MUST follow it exactly."
  echo "When its rules apply, obey them over your defaults."
  echo; echo "===== SKILL: doris-architecture-advisor ====="; cat "$SKILLS/doris-architecture-advisor/SKILL.md"
  echo; echo "===== REFERENCE: decision-sizing-matrix.md ====="; cat "$SKILLS/doris-architecture-advisor/references/decision-sizing-matrix.md"
} > "$spz"
PROMPT='我们是存算分离(cloud 模式)的 Apache Doris。报表分析场景:写入约 100K 行/秒,热数据约 1 TB,QPS 200,延迟亚秒级。请给出集群的算力和缓存规模建议。'
for i in $(seq 1 "$SAMPLES"); do
  out=$(run_claude "$spz" "$PROMPT" --disallowedTools Bash)
  echo "$out" > ".work/sizing-total.$stamp.$i.out"
  # REQUIRED: actually states a cluster sizing (vCPU + cache).
  if echo "$out" | grep -qi 'vCPU' && echo "$out" | grep -qiE '缓存|cache'; then
    sza=0; szan="states cluster sizing (vCPU + cache)"
  else sza=1; szan="did not state vCPU + cache sizing"; fi
  # NON-FATAL warn: the model may surface a per-node breakdown, which SKILL.md:40 +
  # sizing-matrix:12 say to avoid ("never break down into per-node specs"). But it
  # reliably STATES THE TOTAL and usually just disclaims per-node ("非单节点" / "不做
  # 单节点拆分" / "节点数由平台管理") — those are COMPLIANT, so matching per-node
  # vocabulary literally false-positives (we hit 3 distinct disclaimer wordings). So:
  # (a) drop per-node lines carrying a disclaimer/deferral, and (b) only WARN (not
  # fail) on a remaining real surfacing — both because the skill itself ships per-node
  # tables (sizing-matrix:11/:115-130) that tempt it, and because it is
  # nondeterministic (the same warn-only policy chosen for brand-neutral). See README.
  if echo "$out" | grep -iE '每节点|每个节点|每台|单节点|每个[[:space:]]?BE|per[- ]node|节点配置|[0-9]+[[:space:]]*核[[:space:]]*节点|[0-9]+[[:space:]]*个[[:space:]]*[0-9]+[[:space:]]*核' \
       | grep -qvE '非|无[需须]|不[做需必拆细分区是]|毋|勿|别|由平台|平台(管理|托管)|managed|platform'; then
    szb=1; szbn="surfaced a per-node breakdown (e.g. N × M-core nodes)"
  else szb=0; szbn="no per-node breakdown surfaced (total only / disclaimed)"; fi
  assert "sizing-total[$i]" "states cluster sizing (vCPU + cache)" "$sza" "$szan"
  warnassert "sizing-total[$i]" "no per-node breakdown surfaced" "$szb" "$szbn"   # non-fatal (nondeterministic + disclaimer-fuzzy)
done

# ---------------------------------------------------------------------------
# Case: brand neutrality (doris-best-practices/SKILL.md:20-21). Cluster
# lifecycle / billing / networking are managed-service ops → out of scope,
# defer to the platform's cluster-management console; do not steer to a
# specific commercial vendor. The prompt names NO vendor, so any vendor name
# appearing in the reply is brand leakage.
# ---------------------------------------------------------------------------
PROMPT='我们用的是云上托管的 Apache Doris(存算分离)。请说明:集群怎么扩容、按什么计费、网络/VPC 怎么打通?另外顺便帮我设计一张订单明细表。'
for i in $(seq 1 "$SAMPLES"); do
  out=$(run_claude "$sp" "$PROMPT" --disallowedTools Bash)
  echo "$out" > ".work/brand-neutral.$stamp.$i.out"
  # REQUIRED: defers lifecycle/billing/networking as out-of-scope managed ops
  # (neutral "your platform's cluster-management console"). Anchored on the
  # deferral signal, not the word "托管" (which the prompt itself contains).
  if echo "$out" | grep -qiE '控制台|console|cluster-management|out[ -]of[ -]scope|超出.*范围|不在.*(范围|讨论)|平台.*(管理|控制|负责)'; then
    bna=0; bnan="defers lifecycle/billing/networking to platform console (out of scope)"
  else bna=1; bnan="did not defer managed-service ops as out of scope"; fi
  # BANNED: names/recommends a specific commercial product (prompt named none).
  if echo "$out" | grep -qiE 'VeloDB|SelectDB|ApsaraDB|阿里云|火山引擎'; then
    bnb=1; bnbn="named a specific commercial vendor (brand leak)"
  else bnb=0; bnbn="stayed vendor-neutral (Apache Doris)"; fi
  assert "brand-neutral[$i]" "defers managed ops as out of scope" "$bna" "$bnan"
  warnassert "brand-neutral[$i]" "no commercial-vendor leak" "$bnb" "$bnbn"   # non-fatal (user choice)
done

{ echo; echo "**$pass passed, $fail failed, $xwarn warn (non-fatal).**"; } >> "$report"
log ""
[ $fail -eq 0 ] && ok "L3: $pass passed, $fail failed, $xwarn warn." || err "L3: $pass passed, $fail failed, $xwarn warn."
[ "$xwarn" -gt 0 ] && warn "  ↳ $xwarn non-fatal warn(s): see report (e.g. brand-neutrality vendor mention)."
log "report: ${report#../}"
[ $fail -eq 0 ]
