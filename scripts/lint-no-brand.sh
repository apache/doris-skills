#!/usr/bin/env bash
# lint-no-brand.sh — fail if any brand-specific bare string leaks into
# the shared skills/ tree. These should all be expressed via {{...}} placeholders
# or neutralized to "Apache Doris" / "Cloud mode".

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(dirname -- "$SCRIPT_DIR")
SKILLS_DIR=$REPO_ROOT/skills

# Bare brand strings forbidden in shared content
FORBIDDEN='velocli|sdbcli|VELOCLI|SDBCLI|VeloDB|SelectDB|velodb\.cloud|velodb\.io|selectdb\.com|selectdb\.cn|~/\.velodb|~/\.selectdb|\$VELO_|\$SDB_'

if grep -rnE --include='*.md' "$FORBIDDEN" "$SKILLS_DIR"; then
  echo ""
  echo "lint-no-brand: FAIL — bare brand strings found above." >&2
  echo "Replace with the appropriate {{PLACEHOLDER}} or use 'Apache Doris' / 'Cloud mode' wording." >&2
  exit 1
fi

echo "lint-no-brand: ok"
