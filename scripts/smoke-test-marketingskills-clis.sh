#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_MARKETINGSKILLS_REPO="$(cd "${PROJECT_ROOT}/.." && pwd)/marketingskills"
MARKETINGSKILLS_REPO="${DEFAULT_MARKETINGSKILLS_REPO}"

usage() {
  cat <<'EOF'
Usage:
  smoke-test-marketingskills-clis.sh [--marketingskills-repo PATH]

What it checks:
  1. Syntax-check every CLI script in tools/clis/
  2. Run representative dry-run commands for GA4 and Meta Ads
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

abs_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --marketingskills-repo)
      [[ $# -ge 2 ]] || die "--marketingskills-repo requires a value"
      MARKETINGSKILLS_REPO="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_cmd node
require_cmd python3

MARKETINGSKILLS_REPO="$(abs_path "$MARKETINGSKILLS_REPO")"
CLI_DIR="${MARKETINGSKILLS_REPO}/tools/clis"
[[ -d "$CLI_DIR" ]] || die "No CLI directory found at ${CLI_DIR}"

CLIS=()
while IFS= read -r cli; do
  CLIS+=("$cli")
done < <(find "$CLI_DIR" -maxdepth 1 -type f -name '*.js' | sort)
[[ ${#CLIS[@]} -gt 0 ]] || die "No CLI scripts found in ${CLI_DIR}"

echo "Syntax-checking ${#CLIS[@]} marketing CLIs..."
for cli in "${CLIS[@]}"; do
  node --check "$cli"
done
echo "✓ Syntax checks passed"

echo "Running representative dry-run commands..."
GA4_ACCESS_TOKEN="dry-run-token" \
  node "${CLI_DIR}/ga4.js" reports run \
  --property 123456789 \
  --metrics sessions \
  --dimensions date \
  --dry-run >/dev/null

META_ACCESS_TOKEN="dry-run-token" \
META_AD_ACCOUNT_ID="1234567890" \
  node "${CLI_DIR}/meta-ads.js" campaigns list \
  --dry-run >/dev/null

echo "✓ Dry-run checks passed"
echo "Marketingskills CLI smoke test complete."
