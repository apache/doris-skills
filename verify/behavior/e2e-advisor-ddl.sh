#!/usr/bin/env bash
# L3 end-to-end: the strongest behavioral test. Give the architecture-advisor skill a
# workload, let it generate CREATE TABLE DDL, then run that DDL through the real cluster
# (the L1 judge). The "brain" produces the DDL; the live Doris decides if it is valid.
#
# Each generated CREATE TABLE is classified:
#   - created            : Doris accepted it (DDL correct)
#   - valid/capacity     : rejected only for replica/host shortage (1-BE test cluster) —
#                          the DDL passed parsing + constraint validation, so it is correct
#   - INVALID            : parser/constraint error — the advisor produced bad DDL (failure)
#
#   ./e2e-advisor-ddl.sh
# Exit non-zero if any generated DDL is INVALID.

set -uo pipefail
cd "$(dirname "$0")"            # verify/behavior
. ../lib.sh
[ -f ../env.sh ] || { err "verify/env.sh not found"; exit 2; }
# shellcheck source=/dev/null
. ../env.sh
: "${DORIS_HOST:?}"; : "${DORIS_PORT:?}"; : "${DORIS_USER:?}"
SCRATCH_DB="${SCRATCH_DB:-doris_skill_verify}"
case "$SCRATCH_DB" in doris_skill_verify*) ;; *) err "refusing: SCRATCH_DB must start with doris_skill_verify"; exit 2 ;; esac
command -v claude >/dev/null || { err "claude CLI not found"; exit 2; }
SKILLS="$(cd ../../skills && pwd)"
mkdir -p ../reports .work
MYSQL=(mysql -h"$DORIS_HOST" -P"$DORIS_PORT" -u"$DORIS_USER" --batch --connect-timeout=10)
[ -n "${DORIS_PASS:-}" ] && MYSQL+=(-p"$DORIS_PASS")

# Connectivity gate — the live DDL loopback is the whole point, and the model call
# is expensive, so abort early (and clearly) if the cluster is unreachable.
if ! "${MYSQL[@]}" -N -e "SELECT 1" >/dev/null 2>&1; then
  err "cluster $DORIS_HOST:$DORIS_PORT unreachable — cannot run the live DDL loopback."
  err "(connection refused/timeout — check the tunnel/proxy, then re-run.)"
  exit 2
fi

# --- 1. generate DDL via the advisor skill --------------------------------
sp="$PWD/.work/sp-advisor.txt"
{
  echo "You have the following two Apache Doris skills loaded and MUST follow them."
  echo "Produce concrete, executable CREATE TABLE DDL for the user's workload."
  echo; echo "===== SKILL: doris-architecture-advisor ====="; cat "$SKILLS/doris-architecture-advisor/SKILL.md"
  echo; echo "===== SKILL: doris-best-practices ====="; cat "$SKILLS/doris-best-practices/SKILL.md"
} > "$sp"

PROMPT='我们有 5 万个 IoT 设备，每台每 10 秒上报温度、湿度、在线状态。需求：(1) 实时监控大盘，按分钟聚合指标；(2) 按设备 ID 查最新状态（高并发点查）；(3) 保留原始明细 90 天用于问题排查。请用 Apache Doris 设计表结构，直接给出可执行的 CREATE TABLE DDL（含模型、分区、分桶、关键属性）。'

log "== L3 e2e: advisor → DDL → live cluster =="
resp="$PWD/.work/advisor-resp.txt"
if [ "${REUSE:-0}" = 1 ] && [ -s "$resp" ]; then
  log "REUSE=1: reusing existing advisor response (no model call) — $resp"
else
  log "generating DDL via nested claude (this takes a bit)..."
  ( cd /tmp && env -u CLAUDECODE claude -p "$PROMPT" \
      --append-system-prompt "$(cat "$sp")" --disallowedTools Bash --output-format text 2>/dev/null ) > "$resp"
fi
[ -s "$resp" ] || { err "no response from claude"; exit 2; }

# --- 2. extract each CREATE TABLE statement -------------------------------
rm -f .work/ddl_*.sql            # clear stale DDL from any prior run
n=$(python3 - "$resp" "$PWD/.work" <<'PY'
import re, sys, os
txt = open(sys.argv[1]).read(); outdir = sys.argv[2]
blocks = re.findall(r'```sql\s*\n(.*?)```', txt, re.S) or [txt]
sql = '\n'.join(blocks)
# Strip line comments BEFORE splitting on ';': the advisor annotates DDL with
# inline `-- …` comments, and one containing a ';' (e.g. "-- 追加写,无更新;…")
# otherwise splits a statement mid-way, silently dropping its
# PARTITION/DISTRIBUTED/PROPERTIES tail — which Doris cloud then accepts as a
# stub, yielding a FALSE "created". Comments are noise for validation anyway.
sql = re.sub(r'--[^\n]*', '', sql)
stmts = [s.strip() for s in sql.split(';')
         if re.search(r'create\s+table', s, re.I) and not re.search(r'show\s+create', s, re.I)]
for i, s in enumerate(stmts):
    open(os.path.join(outdir, f'ddl_{i}.sql'), 'w').write(s + ';\n')
print(len(stmts))
PY
)
log "advisor produced $n CREATE TABLE statement(s)"
[ "$n" -gt 0 ] || { err "no CREATE TABLE found in advisor output (see $resp)"; exit 1; }

# --- 3. run each against the real cluster ---------------------------------
"${MYSQL[@]}" -e "DROP DATABASE IF EXISTS \`$SCRATCH_DB\`; CREATE DATABASE \`$SCRATCH_DB\`" 2>/dev/null
stamp=$(date +%Y%m%d-%H%M%S); report="../reports/L3e2e-$stamp.md"
{ echo "# L3 e2e advisor→DDL report — $stamp"; echo; echo "workload: IoT 50k devices (dashboard + point-query + 90d detail)"; echo;
  echo "| result | table | note |"; echo "|---|---|---|"; } > "$report"
created=0; capacity=0; invalid=0
for f in .work/ddl_*.sql; do
  [ -f "$f" ] || continue
  tname=$(grep -ioE 'create table( if not exists)?[ `]+[a-zA-Z0-9_.]+' "$f" | head -1 | awk '{print $NF}' | tr -d '`')
  out=$("${MYSQL[@]}" -D "$SCRATCH_DB" < "$f" 2>&1); rc=$?
  if echo "$out" | grep -qiE "can't connect|lost connection|server has gone away|\(2003\)|\(2013\)"; then
    err "lost cluster connection mid-run — aborting (results would be incomplete)."; "${MYSQL[@]}" -e "DROP DATABASE IF EXISTS \`$SCRATCH_DB\`" 2>/dev/null; exit 2
  fi
  if [ $rc -eq 0 ]; then
    created=$((created+1)); ok "created   $tname"
    echo "| ✅ created | \`$tname\` |  |" >> "$report"
  elif echo "$out" | grep -qiE 'replica|enough host|backend|be number|tablet.*alive'; then
    capacity=$((capacity+1)); warn "valid*    $tname  (DDL valid; blocked by 1-BE capacity)"
    echo "| 🟡 valid (capacity) | \`$tname\` | DDL passed validation; replica/host shortage on 1-BE cluster |" >> "$report"
  else
    invalid=$((invalid+1)); err "INVALID   $tname"
    el=$(echo "$out" | grep -i 'ERROR' | head -1 | tr '\n' ' '); dim "        ↳ $el"
    echo "| ❌ INVALID | \`$tname\` | ${el//|/\\|} |" >> "$report"
  fi
done
"${MYSQL[@]}" -e "DROP DATABASE IF EXISTS \`$SCRATCH_DB\`" 2>/dev/null

valid=$((created+capacity))
{ echo; echo "**$valid/$n DDL valid** ($created created, $capacity capacity-blocked); $invalid invalid."; } >> "$report"
log ""
[ $invalid -eq 0 ] && ok "L3 e2e: $valid/$n advisor DDL valid ($created created, $capacity capacity); $invalid invalid." \
                   || err "L3 e2e: $invalid/$n advisor DDL INVALID."
log "full advisor response: ${resp#$PWD/}  |  report: ${report#../}"
[ $invalid -eq 0 ]
