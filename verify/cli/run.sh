#!/usr/bin/env bash
# L2 — CLI-contract verification: confirm doriscli exposes exactly the commands and
# JSON field paths that ../../CLI-CONTRACT.md (in doris-skills) hard-codes. A renamed
# or absent field silently degrades to null in the skill's reasoning, so we assert
# each documented path actually resolves against a live cluster.
#
#   cp ../env.example.sh ../env.sh && edit it     # shared with L1
#   ./run.sh                                       # auto-detects doriscli + HTTP port
#
# Exit code is non-zero if any contracted field is missing (CI-friendly).

set -uo pipefail
cd "$(dirname "$0")"            # verify/cli
. ../lib.sh
[ -f ../env.sh ] || { err "verify/env.sh not found — copy env.example.sh to env.sh and fill it."; exit 2; }
# shellcheck source=/dev/null
. ../env.sh
: "${DORIS_HOST:?set DORIS_HOST in env.sh}"
: "${DORIS_PORT:?set DORIS_PORT in env.sh}"
: "${DORIS_USER:?set DORIS_USER in env.sh}"
SCRATCH_DB="${SCRATCH_DB:-doris_skill_verify}"
case "$SCRATCH_DB" in doris_skill_verify*) ;; *) err "refusing: SCRATCH_DB must start with doris_skill_verify"; exit 2 ;; esac

MYSQL=(mysql -h"$DORIS_HOST" -P"$DORIS_PORT" -u"$DORIS_USER" --batch --connect-timeout=10)
[ -n "${DORIS_PASS:-}" ] && MYSQL+=(-p"$DORIS_PASS")

# --- resolve doriscli binary ----------------------------------------------
resolve_dcli() {
  if [ -n "${DORIS_CLI_PATH:-}" ] && [ -x "${DORIS_CLI_PATH}" ]; then echo "$DORIS_CLI_PATH"; return 0; fi
  local p
  for p in ../../../doris-cli/target/release/doriscli ../../../doris-cli/target/debug/doriscli \
           ../../doris-cli/target/release/doriscli; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  command -v doriscli 2>/dev/null && return 0
  return 1
}
DCLI="$(resolve_dcli)" || { err "doriscli binary not found (set DORIS_CLI_PATH in env.sh)"; exit 2; }

# --- resolve FE HTTP port (auto-detect from SHOW FRONTENDS if unset) -------
HTTP_PORT="${DORIS_HTTP_PORT:-}"
if [ -z "$HTTP_PORT" ]; then
  # NOTE: no -N here — it suppresses the \G field labels we sed on (HttpPort:).
  HTTP_PORT=$("${MYSQL[@]}" -e "SHOW FRONTENDS\G" 2>/dev/null | sed -n 's/.*HttpPort: *//p' | head -1 | tr -d '[:space:]')
  [ -z "$HTTP_PORT" ] && HTTP_PORT=8030
fi

# doriscli stateless mode: HOST+USER set => never touches ~/.doris files.
export DORIS_HOST DORIS_PORT DORIS_USER
export DORIS_PASSWORD="${DORIS_PASS:-}"
export DORIS_HTTP_PORT="$HTTP_PORT"
dcli() { "$DCLI" "$@" --format json 2>/dev/null; }

log "== L2 CLI-contract verification =="
log "doriscli: $DCLI ($("$DCLI" --version 2>/dev/null))"
log "cluster:  $DORIS_HOST:$DORIS_PORT  http:$HTTP_PORT"

# connectivity gate
if ! dcli auth status | jq -e '.mysql_status=="connected"' >/dev/null 2>&1; then
  err "doriscli cannot connect (auth status mysql_status != connected). Check env.sh / HTTP port."
  dcli auth status | jq -c '{mysql_status,http_status}' 2>/dev/null || true
  exit 2
fi

# --- seed deterministic data (via mysql; seeding is setup, not the test) ---
"${MYSQL[@]}" <<SQL >/dev/null 2>&1
DROP DATABASE IF EXISTS \`$SCRATCH_DB\`;
CREATE DATABASE \`$SCRATCH_DB\`;
USE \`$SCRATCH_DB\`;
CREATE TABLE dim_product (product_id INT NOT NULL, name VARCHAR(50), category VARCHAR(30))
  UNIQUE KEY(product_id) DISTRIBUTED BY HASH(product_id) BUCKETS 3
  PROPERTIES("enable_unique_key_merge_on_write"="true","replication_num"="1");
INSERT INTO dim_product VALUES (1,"a","x"),(2,"b","x"),(3,"c","y"),(4,"d","y"),(5,"e","z");
CREATE TABLE sales (id BIGINT NOT NULL, product_id INT NOT NULL, dt DATETIME NOT NULL, amount DECIMAL(18,2))
  DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 4 PROPERTIES("replication_num"="1");
INSERT INTO sales SELECT number, (number % 5)+1, "2025-01-01 12:00:00", (number % 100)+1 FROM numbers("number"="500");
ANALYZE TABLE sales WITH SYNC;
ANALYZE TABLE dim_product WITH SYNC;
SQL

# --- report setup ----------------------------------------------------------
mkdir -p ../reports
stamp=$(date +%Y%m%d-%H%M%S)
report="../reports/L2-$stamp.md"
{
  echo "# L2 CLI-contract report — $stamp"
  echo
  echo "- doriscli: \`$("$DCLI" --version 2>/dev/null)\`  cluster: \`$DORIS_HOST:$DORIS_PORT\` http \`$HTTP_PORT\`"
  echo
  echo "| result | command | contract field | note |"
  echo "|---|---|---|---|"
} > "$report"
pass=0; fail=0; xfail=0; xpass=0

assert() {  # assert <cmd-label> <field-label> <json> <jq-bool-expr> [note]
  local cmd="$1" fld="$2" json="$3" expr="$4" note="${5:-}"
  if printf '%s' "$json" | jq -e "$expr" >/dev/null 2>&1; then
    pass=$((pass+1)); ok "PASS  $cmd → $fld"
    echo "| ✅ pass | \`$cmd\` | $fld | $note |" >> "$report"
  else
    fail=$((fail+1)); err "FAIL  $cmd → $fld  (missing/null)"
    echo "| ❌ FAIL | \`$cmd\` | $fld | missing/null on this cluster${note:+ — $note} |" >> "$report"
  fi
}

# xassert — like assert, but the field is a KNOWN doriscli limitation on this
# cluster, so a miss is EXPECTED (xfail, non-fatal). If it unexpectedly resolves,
# that is an xpass: the marker is stale and should be removed. Neither counts as
# a hard failure, so the suite stays green on known-doriscli-only gaps but flags
# loudly when reality changes.
xassert() {  # xassert <cmd> <field> <json> <jq-bool-expr> <reason>
  local cmd="$1" fld="$2" json="$3" expr="$4" reason="$5"
  if printf '%s' "$json" | jq -e "$expr" >/dev/null 2>&1; then
    xpass=$((xpass+1)); warn "XPASS $cmd → $fld  (now resolves — remove xfail?)"
    echo "| 🎉 xpass | \`$cmd\` | $fld | now resolves on this cluster — remove the xfail marker ($reason) |" >> "$report"
  else
    xfail=$((xfail+1)); dim "xfail $cmd → $fld  (known: $reason)"
    echo "| 🟡 xfail | \`$cmd\` | $fld | known doriscli gap — $reason |" >> "$report"
  fi
}

# --- auth status -----------------------------------------------------------
J=$(dcli auth status)
assert "auth status" "mysql_status"     "$J" '.mysql_status != null'
assert "auth status" "http_status"      "$J" '.http_status != null'
assert "auth status" "http_probe"       "$J" '.http_probe != null'
assert "auth status" "backends[].alive" "$J" '(.backends|type=="array") and (.backends[0].alive != null)'

# --- tablet ----------------------------------------------------------------
J=$(dcli tablet "$SCRATCH_DB.sales")
assert "tablet" "model"             "$J" '.model != null'
assert "tablet" "bucket_key"        "$J" '.bucket_key != null'
assert "tablet" "bucket_count"      "$J" '.bucket_count != null'
assert "tablet" "sort_key"          "$J" '.sort_key != null'
assert "tablet" "total_rows"        "$J" '.total_rows != null'
assert "tablet" "health.tablet_skew" "$J" '.health.tablet_skew != null'
assert "tablet" "columns[].ndv"     "$J" '(.columns|type=="array") and (.columns[0].ndv != null)'

# --- sql (need query_id to chain into profile get) -------------------------
QJOIN='SELECT d.category,count(*) c,sum(s.amount) t FROM '"$SCRATCH_DB"'.sales s JOIN '"$SCRATCH_DB"'.dim_product d ON s.product_id=d.product_id WHERE s.amount>10 GROUP BY d.category'
J=$(dcli sql "$QJOIN" --profile --set 'profile_level=2')
assert "sql --profile" "query_id" "$J" '.query_id != null'
QID=$(printf '%s' "$J" | jq -r '.query_id // empty')
# a second profiled query so `profile diff` has two query_ids to compare
QSCAN='SELECT count(*) c FROM '"$SCRATCH_DB"'.sales WHERE amount>50'
J2=$(dcli sql "$QSCAN" --profile --set 'profile_level=2')
QID2=$(printf '%s' "$J2" | jq -r '.query_id // empty')

# --- profile list ----------------------------------------------------------
J=$(dcli profile list --limit 5)
assert "profile list" "[].query_id" "$J" '(type=="array") and (.[0].query_id != null)'

# --- profile get (best shot: profile_level=2 was set above) ----------------
# retry a few times without sleeping (profile may need a beat to land on the FE)
J=""; for _ in 1 2 3 4 5; do J=$(dcli profile get "$QID"); printf '%s' "$J" | jq -e '(.operators|length)>0' >/dev/null 2>&1 && break; done
assert "profile get" "summary.total_time_ms"      "$J" '.summary.total_time_ms != null'
assert "profile get" "operators[]"                "$J" '(.operators|type=="array") and ((.operators|length)>0)' "needs profile_level=2 AND doriscli must decode a large profile"
# Fixed in doriscli dd3f417 (parser: keep per-operator counters when a PlanInfo
# block precedes them) — was xfail on the pre-fix 0.1.x build, verified resolved
# on 5.0.0 cloud. Back to a normal assert. (xassert helper retained for future gaps.)
assert "profile get" "query_stats.total_scan_rows" "$J" '.query_stats.total_scan_rows != null'
assert "profile get" "time_breakdown.plan"        "$J" '.time_breakdown.plan != null'
assert "profile get" "scanned_tables.<t>"         "$J" '(.scanned_tables|type=="object") and ((.scanned_tables|length)>0)'

# --- profile diff (two profiled queries; shares profile get's fetch path) --
J=""; for _ in 1 2 3 4 5; do J=$(dcli profile diff "$QID" "$QID2"); printf '%s' "$J" | jq -e '.slow.query_id != null' >/dev/null 2>&1 && break; done
assert "profile diff" "slow.query_id"    "$J" '.slow.query_id != null'
assert "profile diff" "fast.query_id"    "$J" '.fast.query_id != null'
assert "profile diff" "operator_diffs[]" "$J" '(.operator_diffs|type=="array")'
assert "profile diff" "time_ratio"       "$J" '.time_ratio != null'

# --- profile history (p50/p99 trend from audit_log; independent fetch path) -
# Shape check: command + JSON contract resolve even with 0 matches
# ({executions:0, entries:[]}). Fails only if audit_log is inaccessible.
J=$(dcli profile history "sales" --days 7 --limit 5)
assert "profile history" "executions" "$J" '.executions != null'
assert "profile history" "entries[]"  "$J" '(.entries|type=="array")'

# --- use (env switch) — a state change, not a JSON-contract command; not
# exercised in L2's stateless mode (HOST/USER set => no named env to switch).
# Assert only that the command still exists in doriscli's CLI surface.
if "$DCLI" use --help >/dev/null 2>&1; then
  pass=$((pass+1)); ok "PASS  use → command exists (stateless: switch not exercised)"
  echo "| ✅ pass | \`use\` | command exists | stateless harness: env-switch not exercised |" >> "$report"
else
  fail=$((fail+1)); err "FAIL  use → command missing (use --help non-zero)"
  echo "| ❌ FAIL | \`use\` | command exists | \`use --help\` did not exit 0 |" >> "$report"
fi

# --- cleanup ---------------------------------------------------------------
[ "${KEEP:-0}" = 1 ] || "${MYSQL[@]}" -e "DROP DATABASE IF EXISTS \`$SCRATCH_DB\`" >/dev/null 2>&1

{ echo; echo "**$pass passed, $fail failed, $xfail xfail, $xpass xpass** — $((pass+fail+xfail+xpass)) contract checks."; } >> "$report"
log ""
sumline="L2: $pass passed, $fail failed, $xfail xfail, $xpass xpass."
[ $fail -eq 0 ] && ok "$sumline" || err "$sumline"
[ "$xpass" -gt 0 ] && warn "  ↳ $xpass xpass: a known-fail now resolves — review/remove the xfail marker."
log "report: ${report#../}"
[ $fail -eq 0 ]
