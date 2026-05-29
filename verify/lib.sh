# shellcheck shell=bash
# Shared helpers for the doris-skills verification suite.
# Sourced by run.sh (and later by L2/L3 runners). No side effects on source.

# --- logging ---------------------------------------------------------------
c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_rst=$'\033[0m'
log()  { printf '%s\n' "$*" >&2; }
ok()   { printf '%s%s%s\n' "$c_grn" "$*" "$c_rst" >&2; }
warn() { printf '%s%s%s\n' "$c_yel" "$*" "$c_rst" >&2; }
err()  { printf '%s%s%s\n' "$c_red" "$*" "$c_rst" >&2; }
dim()  { printf '%s%s%s\n' "$c_dim" "$*" "$c_rst" >&2; }

# --- version compare -------------------------------------------------------
# vge CUR MIN -> exit 0 if CUR >= MIN. Empty MIN or empty CUR => 0 (don't skip).
vge() {
  [ -z "${2:-}" ] && return 0
  [ -z "${1:-}" ] && return 0
  local smaller
  smaller=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)
  [ "$smaller" = "$2" ]
}

# --- mode match ------------------------------------------------------------
# mode_ok TAG -> 0 if a case tagged TAG applies to the current $DORIS_MODE.
mode_ok() {
  case "${1:-any}" in
    any|"") return 0 ;;
    "$DORIS_MODE") return 0 ;;
    *) return 1 ;;
  esac
}

# --- header field ----------------------------------------------------------
# hdr KEY FILE -> value of the leading "-- KEY: value" comment, or empty.
hdr() {
  grep -m1 "^-- $1:" "$2" 2>/dev/null | sed "s/^-- $1:[[:space:]]*//"
}
