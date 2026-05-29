#!/usr/bin/env bash
# L1 — knowledge-layer verification: run every DDL case under ddl/ against a
# real Doris cluster and check it is ACCEPTED or REJECTED exactly as the skill
# claims. Pure ground-truth: no LLM involved.
#
# Usage:
#   cp env.example.sh env.sh && $EDITOR env.sh   # fill connection info
#   ./run.sh                                      # run all cases
#   KEEP=1 ./run.sh                               # keep the scratch db for inspection
#   ./run.sh ddl/gotchas                          # run only one subdir
#
# Exit code is non-zero if any case FAILs (CI-friendly).

set -uo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib.sh
. ./lib.sh

# --- config ----------------------------------------------------------------
[ -f env.sh ] || { err "verify/env.sh not found — copy env.example.sh to env.sh and fill it."; exit 2; }
# shellcheck source=/dev/null
. ./env.sh
: "${DORIS_HOST:?set DORIS_HOST in env.sh}"
: "${DORIS_PORT:?set DORIS_PORT in env.sh}"
: "${DORIS_USER:?set DORIS_USER in env.sh}"
DORIS_PASS="${DORIS_PASS:-}"
DORIS_MODE="${DORIS_MODE:-integrated}"
DORIS_VERSION="${DORIS_VERSION:-}"
SCRATCH_DB="${SCRATCH_DB:-doris_skill_verify}"
CASE_DIR="${1:-ddl}"

# Guard: never let a misconfigured env.sh point DROP DATABASE at a real db.
case "$SCRATCH_DB" in
  doris_skill_verify*) ;;
  *) err "refusing to run: SCRATCH_DB='$SCRATCH_DB' must start with 'doris_skill_verify' (it gets DROPped)."; exit 2 ;;
esac

MYSQL=(mysql -h"$DORIS_HOST" -P"$DORIS_PORT" -u"$DORIS_USER" --batch --raw --connect-timeout=10)
[ -n "$DORIS_PASS" ] && MYSQL+=(-p"$DORIS_PASS")
mysql_db() { "${MYSQL[@]}" -D "$SCRATCH_DB" "$@"; }

# --- step 0: connectivity + identity --------------------------------------
log "== L1 knowledge-layer verification =="
if ! "${MYSQL[@]}" -N -e "SELECT 1" >/dev/null 2>conn.err; then
  err "cannot connect to $DORIS_HOST:$DORIS_PORT as $DORIS_USER"; sed 's/^/  /' conn.err >&2; rm -f conn.err; exit 2
fi
rm -f conn.err
# Note: version() returns the MySQL-compat string (~5.7.x), NOT the Doris version,
# so it is informational only. Version gating uses the user-set DORIS_VERSION.
detected=$("${MYSQL[@]}" -N -e "SELECT version()" 2>/dev/null | head -n1)
log "host=$DORIS_HOST:$DORIS_PORT  mode=$DORIS_MODE  gating-version=${DORIS_VERSION:-<none: all cases run>}  (mysql-compat reports: ${detected:-?})"
log "scratch db=$SCRATCH_DB"

# fresh scratch db every run
"${MYSQL[@]}" -e "DROP DATABASE IF EXISTS \`$SCRATCH_DB\`; CREATE DATABASE \`$SCRATCH_DB\`" 2>/dev/null \
  || { err "could not (re)create scratch db $SCRATCH_DB"; exit 2; }

# --- report setup ----------------------------------------------------------
mkdir -p reports
stamp=$(date +%Y%m%d-%H%M%S)
report="reports/L1-$stamp.md"
{
  echo "# L1 verification report — $stamp"
  echo
  echo "- host: \`$DORIS_HOST:$DORIS_PORT\`  mode: \`$DORIS_MODE\`  version: \`${DORIS_VERSION:-unknown}\`"
  echo
  echo "| result | case | expect | ref | note |"
  echo "|---|---|---|---|---|"
} > "$report"

pass=0; fail=0; skip=0

# --- run one case ----------------------------------------------------------
run_case() {
  local f="$1" expect base ref desc minv mode errlike out rc result note
  base="${f#./}"
  case "$f" in
    *.pass.sql) expect=pass ;;
    *.fail.sql) expect=fail ;;
    *) return ;;  # not a case file
  esac
  ref=$(hdr ref "$f");      desc=$(hdr desc "$f")
  minv=$(hdr min_version "$f"); mode=$(hdr mode "$f"); errlike=$(hdr errlike "$f")

  if ! mode_ok "$mode"; then
    skip=$((skip+1)); dim "SKIP  $base  (mode=$mode, cluster=$DORIS_MODE)"
    echo "| ⏭ skip | \`$base\` | $expect | $ref | mode $mode≠$DORIS_MODE |" >> "$report"; return
  fi
  if ! vge "$DORIS_VERSION" "$minv"; then
    skip=$((skip+1)); dim "SKIP  $base  (needs >= $minv, cluster $DORIS_VERSION)"
    echo "| ⏭ skip | \`$base\` | $expect | $ref | needs ≥$minv |" >> "$report"; return
  fi

  out=$(mysql_db < "$f" 2>&1); rc=$?

  if [ "$expect" = pass ]; then
    if [ $rc -eq 0 ]; then result=PASS; note=""; else result=FAIL; note="expected accept, got error"; fi
  else  # expect fail
    if [ $rc -ne 0 ]; then
      if [ -n "$errlike" ] && ! grep -qiF "$errlike" <<<"$out"; then
        result=FAIL; note="rejected, but NOT for expected reason ('$errlike')"
      else
        result=PASS; note=""
      fi
    else
      result=FAIL; note="expected reject, but it was ACCEPTED"
    fi
  fi

  # Doris puts the real reason on lines AFTER the "ERROR ... detailMessage =" line
  # (parser errors especially), so collapse the whole error to one line for the report.
  local errline
  errline=$(printf '%s' "$out" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ *//; s/ *$//')
  [ "${#errline}" -gt 240 ] && errline="${errline:0:240}…"
  if [ "$result" = PASS ]; then
    pass=$((pass+1)); ok "PASS  $base  ${desc:+— $desc}"
    echo "| ✅ pass | \`$base\` | $expect | $ref | ${errline:+got: ${errline//|/\\|}} |" >> "$report"
  else
    fail=$((fail+1)); err "FAIL  $base  — $note"
    [ -n "$errline" ] && dim "        ↳ $errline"
    echo "| ❌ FAIL | \`$base\` | $expect | $ref | $note ${errline:+— ${errline//|/\\|}} |" >> "$report"
  fi
}

# --- iterate ---------------------------------------------------------------
# bash 3.2 (macOS default) has no mapfile, and `"${arr[@]}"` on an empty array
# trips `set -u` there — so fill portably and guard the empty case.
files=()
while IFS= read -r line; do files+=("$line"); done < <(find "$CASE_DIR" -name '*.sql' | sort)
if [ "${#files[@]}" -eq 0 ]; then
  warn "no .sql cases under $CASE_DIR"
else
  for f in "${files[@]}"; do run_case "$f"; done
fi

# --- cleanup ---------------------------------------------------------------
if [ "${KEEP:-0}" = 1 ]; then
  warn "KEEP=1 — leaving scratch db $SCRATCH_DB for inspection"
else
  "${MYSQL[@]}" -e "DROP DATABASE IF EXISTS \`$SCRATCH_DB\`" 2>/dev/null
fi

# --- summary ---------------------------------------------------------------
{ echo; echo "**$pass passed, $fail failed, $skip skipped** — $((pass+fail+skip)) cases."; } >> "$report"
log ""
[ $fail -eq 0 ] && ok "L1: $pass passed, $fail failed, $skip skipped." || err "L1: $pass passed, $fail failed, $skip skipped."
log "report: $report"
[ $fail -eq 0 ]
