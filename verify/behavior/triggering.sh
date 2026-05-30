#!/usr/bin/env bash
# L3 — triggering accuracy: does each skill's `description` frontmatter cause Claude's
# skill ROUTER to INVOKE the skill on in-scope prompts and stay silent on out-of-scope
# ones?
#
# This needs a DIFFERENT harness than run.sh. run.sh force-injects the skill text via
# --append-system-prompt, which BYPASSES the router — so it cannot test triggering at all.
# Here we instead install the repo's two skills into an ISOLATED project `.claude/skills/`
# (so the global look-alike `velodb-best-practices` and every other ~/.claude skill are
# excluded), drive `claude -p` with NO injection, and read the REAL activation signal from
# stream-json: a `tool_use` event named "Skill" whose `.input.skill` is the invoked skill.
# Detection is STRUCTURAL, not content-matching — the base model already knows Doris, so
# prose markers ("DISTRIBUTED BY", …) prove nothing about whether the skill fired.
#
#   ./triggering.sh             # SAMPLES=1 per prompt
#   SAMPLES=3 ./triggering.sh   # repeat (the router is nondeterministic)
# Exit non-zero on any hard failure. Verified against claude 2.1.158.

set -uo pipefail
export LC_ALL="${LC_ALL_OVERRIDE:-en_US.UTF-8}" LANG="${LC_ALL_OVERRIDE:-en_US.UTF-8}"
cd "$(dirname "$0")"            # verify/behavior
. ../lib.sh
SKILLS_SRC="$(cd ../../skills && pwd)"
SAMPLES="${SAMPLES:-1}"
command -v claude >/dev/null || { err "claude CLI not found on PATH"; exit 2; }
command -v jq     >/dev/null || { err "jq not found on PATH"; exit 2; }

mkdir -p ../reports .work
stamp=$(date +%Y%m%d-%H%M%S)
report="../reports/L3trigger-$stamp.md"
{ echo "# L3 triggering report — $stamp"; echo; echo "| result | case | scope | expected | invoked |"; echo "|---|---|---|---|---|"; } > "$report"
pass=0; fail=0

assert() {  # assert <case> <check> <pass?0/1> <scope> <expected> <invoked>
  local case="$1" chk="$2" okflag="$3" scope="${4:-}" exp="${5:-}" inv="${6:-—}"
  if [ "$okflag" = 0 ]; then
    pass=$((pass+1)); ok "PASS  $case → $chk  [invoked: ${inv:-—}]"
    echo "| ✅ pass | $case | $scope | $exp | ${inv:-—} |" >> "$report"
  else
    fail=$((fail+1)); err "FAIL  $case → $chk  [invoked: ${inv:-—}]"
    echo "| ❌ FAIL | $case | $scope | $exp | ${inv:-—} |" >> "$report"
  fi
}

# --- isolated skills env ---------------------------------------------------
# Only the repo's 2 skills are discoverable: --setting-sources local,project drops the
# global ~/.claude skills (incl. velodb-best-practices), and a project .claude/skills/
# with just these two supplies them. enabledSkills whitelists ours as belt-and-suspenders.
ENV_DIR="$PWD/.work/trigger-env"
rm -rf "$ENV_DIR"; mkdir -p "$ENV_DIR/.claude/skills"
cp -r "$SKILLS_SRC/doris-best-practices" "$SKILLS_SRC/doris-architecture-advisor" "$ENV_DIR/.claude/skills/"
cat > "$ENV_DIR/.claude/settings.json" <<'JSON'
{ "enabledSkills": ["doris-best-practices", "doris-architecture-advisor"] }
JSON

# --disallowedTools Bash prevents shell side-effects (e.g. a skill reaching for
# cli-investigation). It MUST sit before --output-format, not last: --disallowedTools is
# variadic (<tools...>) and would otherwise swallow the positional prompt. The Skill tool
# stays available, so the trigger still fires and is recorded as a `tool_use`.
ARGS=(--settings "$ENV_DIR/.claude/settings.json" --setting-sources "local,project"
      --disallowedTools Bash --output-format stream-json --verbose)

# raw_run <prompt> -> raw stream-json on stdout
raw_run() { ( cd "$ENV_DIR" && env -u CLAUDECODE claude -p "${ARGS[@]}" "$1" </dev/null 2>/dev/null ); }
# skills invoked in a run: the set of .input.skill over Skill tool_use events (space-sep)
invoked_skills() { jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill' 2>/dev/null | sort -u | tr '\n' ' '; }

log "== L3 triggering accuracy (SAMPLES=$SAMPLES) =="

# --- 0. isolation precondition --------------------------------------------
# Fail loud if the global look-alike leaks in, or if our skills are missing — either way
# every downstream trigger assertion would be meaningless.
avail=$(raw_run "hi" | jq -r 'select(.type=="system" and .subtype=="init") | .skills[]?' 2>/dev/null | sort | tr '\n' ' ')
log "available skills in isolated env: [${avail:-<none>}]"
case " $avail " in *" velodb-best-practices "*) err "ISOLATION BROKEN: global velodb-best-practices is visible — aborting"; exit 2 ;; esac
case " $avail " in
  *" doris-best-practices "*) : ;; *) err "isolation: doris-best-practices not visible — aborting (test would be meaningless)"; exit 2 ;;
esac
case " $avail " in
  *" doris-architecture-advisor "*) : ;; *) err "isolation: doris-architecture-advisor not visible — aborting"; exit 2 ;;
esac
ok "isolation OK — repo skills visible, global look-alike excluded"

# trigger_case <label> <in|out> <expected-hint> <prompt>
#   in  → a skill MUST be invoked (which one is logged; the two skills overlap by design)
#   out → NO skill may be invoked
trigger_case() {
  local label="$1" scope="$2" hint="$3" prompt="$4" i raw ranok inv invset okflag
  for i in $(seq 1 "$SAMPLES"); do
    raw=$(raw_run "$prompt"); printf '%s' "$raw" > ".work/trigger-$label.$stamp.$i.jsonl"
    # Guard: only trust an empty `invoked` if the run actually SUCCEEDED — otherwise an
    # errored/empty call would masquerade as "out-of-scope, no trigger" (a false pass).
    ranok=$(printf '%s' "$raw" | jq -rs 'any(.[]?; .type=="result" and (.is_error==false))' 2>/dev/null)
    inv=$(printf '%s' "$raw" | invoked_skills); invset="${inv// /}"
    if [ "$ranok" != true ]; then
      assert "trigger:$label[$i]" "claude run completed" 1 "$scope" "$hint" "ERRORED / no success result"
      continue
    fi
    if [ "$scope" = in ]; then
      [ -n "$invset" ] && okflag=0 || okflag=1
      assert "trigger:$label[$i]" "in-scope → a skill fires" "$okflag" "$scope" "$hint" "$inv"
    else
      [ -z "$invset" ] && okflag=0 || okflag=1
      assert "trigger:$label[$i]" "out-of-scope → no skill fires" "$okflag" "$scope" "$hint" "$inv"
    fi
  done
}

# IN-SCOPE — must trigger a skill --------------------------------------------
trigger_case "design-iot"   in  "doris-architecture-advisor" \
  '我们有 5 万个 IoT 设备每 10 秒上报温湿度数据,请帮我从零设计 Apache Doris 的表结构、分区和分桶方案。'
trigger_case "review-ddl"   in  "doris-best-practices" \
  '帮我 review 这条 Apache Doris 建表语句是否符合最佳实践:CREATE TABLE t (id INT, ts DATETIME) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 4;'
# The distinctive one: a legacy-stack migration that NEVER names Apache Doris — both skill
# descriptions claim this should trigger ("…even when Apache Doris is not named explicitly").
trigger_case "migrate-es"   in  "any (ES→? , Doris unnamed)" \
  '我们现在用 Elasticsearch 存日志做检索和分析,数据量大、查询慢、成本又高,想换一个更省成本的实时分析数据库,有什么方案?'

# OUT-OF-SCOPE — must NOT trigger any skill ----------------------------------
trigger_case "trivial-code" out "(none)" '用 Python 写一个把字符串反转的函数。'
trigger_case "general-knowledge" out "(none)" '推荐三本经典科幻小说,并各写一句话简介。'

{ echo; echo "**$pass passed, $fail failed.**"; } >> "$report"
log ""
[ $fail -eq 0 ] && ok "L3 triggering: $pass passed, $fail failed." || err "L3 triggering: $pass passed, $fail failed."
log "report: ${report#../}"
[ $fail -eq 0 ]
