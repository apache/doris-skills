#!/usr/bin/env bash
# render.sh — render shared-repo skills with brand placeholder values.
#
# Usage:
#   render.sh <brand_values_yaml> <out_dir>
#
# The shared skill source is assumed to live at <repo_root>/skills/ where
# <repo_root> is the parent directory of this script.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <brand_values_yaml> <out_dir>" >&2
  exit 2
fi

VALUES_FILE=$1
OUT_DIR=$2

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(dirname -- "$SCRIPT_DIR")
SHARED_SKILLS_DIR=$REPO_ROOT/skills

if [[ ! -f $VALUES_FILE ]]; then
  echo "error: values file not found: $VALUES_FILE" >&2
  exit 2
fi
if [[ ! -d $SHARED_SKILLS_DIR ]]; then
  echo "error: shared skills dir not found: $SHARED_SKILLS_DIR" >&2
  exit 2
fi

# Extract values from yaml (simple grep — only top-level scalar keys supported)
get_val() {
  local key=$1
  grep -E "^${key}:" "$VALUES_FILE" | head -1 | sed -E "s/^${key}:[[:space:]]*//; s/^['\"]//; s/['\"]$//"
}

CLI=$(get_val cli)
CLI_PATH_ENV=$(get_val cli_path_env)
PRODUCT_NAME=$(get_val product_name)
CLOUD_PRODUCT_NAME=$(get_val cloud_product_name)
CLOUD_OPS_SKILL=$(get_val cloud_ops_skill)

# Validate all 5 placeholders are set
missing=()
[[ -z $CLI ]]                && missing+=(cli)
[[ -z $CLI_PATH_ENV ]]       && missing+=(cli_path_env)
[[ -z $PRODUCT_NAME ]]       && missing+=(product_name)
[[ -z $CLOUD_PRODUCT_NAME ]] && missing+=(cloud_product_name)
[[ -z $CLOUD_OPS_SKILL ]]    && missing+=(cloud_ops_skill)
if (( ${#missing[@]} > 0 )); then
  echo "error: brand.values.yaml missing keys: ${missing[*]}" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

# Render every .md under skills/ into the same path under $OUT_DIR
find "$SHARED_SKILLS_DIR" -type f | while read -r src; do
  rel=${src#"$SHARED_SKILLS_DIR/"}
  dst=$OUT_DIR/$rel
  mkdir -p "$(dirname "$dst")"
  case $src in
    *.md)
      sed \
        -e "s|{{CLI}}|${CLI}|g" \
        -e "s|{{CLI_PATH_ENV}}|${CLI_PATH_ENV}|g" \
        -e "s|{{PRODUCT_NAME}}|${PRODUCT_NAME}|g" \
        -e "s|{{CLOUD_PRODUCT_NAME}}|${CLOUD_PRODUCT_NAME}|g" \
        -e "s|{{CLOUD_OPS_SKILL}}|${CLOUD_OPS_SKILL}|g" \
        "$src" > "$dst"
      ;;
    *)
      cp "$src" "$dst"
      ;;
  esac
done

# Verify: no {{ residue in output
if grep -rEln '\{\{[A-Z_]+\}\}' "$OUT_DIR" >/dev/null; then
  echo "error: unrendered placeholder(s) found in output:" >&2
  grep -rEn '\{\{[A-Z_]+\}\}' "$OUT_DIR" | head >&2
  exit 3
fi

echo "render: ok -> $OUT_DIR"
