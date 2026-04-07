#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_MARKETINGSKILLS_REPO="$(cd "${PROJECT_ROOT}/.." && pwd)/marketingskills"

PROFILE_NAME="marketing"
MARKETINGSKILLS_REPO="${DEFAULT_MARKETINGSKILLS_REPO}"
WORKSPACE="${HOME}/hermes-marketing-workspace"
CLONE_CONFIG=0

usage() {
  cat <<'EOF'
Usage:
  setup-marketingskills-profile.sh [options]

Options:
  --profile NAME                Hermes profile name to configure (default: marketing)
  --marketingskills-repo PATH   Path to the marketingskills repo (default: ../marketingskills)
  --workspace PATH              Workspace the marketing agent should use
                                (default: ~/hermes-marketing-workspace)
  --clone-config                Create the Hermes profile by cloning config/.env/SOUL.md
                                from the active profile
  --help                        Show this help

What this script does:
  1. Creates a dedicated Hermes profile if needed
  2. Mounts marketingskills as an external read-only skill directory
  3. Sets the profile's terminal cwd to a dedicated marketing workspace
  4. Seeds a workspace AGENTS.md and product-marketing-context template
  5. Writes repo/workspace helper vars into the profile .env
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

render_template() {
  local src="$1"
  local dst="$2"

  if [[ -e "$dst" ]]; then
    echo "Skipping existing file: $dst"
    return 0
  fi

  python3 - "$src" "$dst" "$PROFILE_NAME" "$MARKETINGSKILLS_REPO" "$WORKSPACE" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
profile_name = sys.argv[3]
repo = sys.argv[4]
workspace = sys.argv[5]

content = src.read_text(encoding="utf-8")
content = content.replace("__PROFILE_NAME__", profile_name)
content = content.replace("__MARKETINGSKILLS_REPO__", repo)
content = content.replace("__WORKSPACE__", workspace)
dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text(content, encoding="utf-8")
PY
}

upsert_env_value() {
  local env_file="$1"
  local key="$2"
  local value="$3"

  python3 - "$env_file" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]

lines = []
if path.exists():
    lines = path.read_text(encoding="utf-8").splitlines()

filtered = []
prefix = f"{key}="
for line in lines:
    if line.startswith(prefix):
        continue
    filtered.append(line)

filtered.append(f"{key}={value}")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(filtered).rstrip() + "\n", encoding="utf-8")
PY
}

append_env_block_once() {
  local env_file="$1"
  local marker="# Marketing skills tool credentials"

  if grep -Fq "$marker" "$env_file" 2>/dev/null; then
    return 0
  fi

  cat >>"$env_file" <<'EOF'

# Marketing skills tool credentials
# Fill in only the platforms you actually want the agent to operate.
# Examples:
# GA4_ACCESS_TOKEN=
# META_ACCESS_TOKEN=
# META_AD_ACCOUNT_ID=
# RESEND_API_KEY=
# GOOGLE_ADS_TOKEN=
# GOOGLE_ADS_DEVELOPER_TOKEN=
# GOOGLE_ADS_CUSTOMER_ID=
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value"
      PROFILE_NAME="$2"
      shift 2
      ;;
    --marketingskills-repo)
      [[ $# -ge 2 ]] || die "--marketingskills-repo requires a value"
      MARKETINGSKILLS_REPO="$2"
      shift 2
      ;;
    --workspace)
      [[ $# -ge 2 ]] || die "--workspace requires a value"
      WORKSPACE="$2"
      shift 2
      ;;
    --clone-config)
      CLONE_CONFIG=1
      shift
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

require_cmd hermes
require_cmd python3
require_cmd node

MARKETINGSKILLS_REPO="$(abs_path "$MARKETINGSKILLS_REPO")"
WORKSPACE="$(abs_path "$WORKSPACE")"

[[ -d "${MARKETINGSKILLS_REPO}/skills" ]] || die "No skills directory found at ${MARKETINGSKILLS_REPO}/skills"
[[ -d "${MARKETINGSKILLS_REPO}/tools/clis" ]] || die "No CLI tools directory found at ${MARKETINGSKILLS_REPO}/tools/clis"
[[ -f "${PROJECT_ROOT}/docs/templates/marketingskills-workspace-AGENTS.md.template" ]] || die "Workspace AGENTS template missing"
[[ -f "${PROJECT_ROOT}/docs/templates/product-marketing-context.md.template" ]] || die "Product marketing context template missing"

PROFILE_DIR="${HOME}/.hermes/profiles/${PROFILE_NAME}"

if [[ -d "$PROFILE_DIR" ]]; then
  echo "Using existing Hermes profile: ${PROFILE_NAME}"
else
  echo "Creating Hermes profile: ${PROFILE_NAME}"
  if [[ "$CLONE_CONFIG" -eq 1 ]]; then
    hermes profile create "${PROFILE_NAME}" --clone
  else
    hermes profile create "${PROFILE_NAME}"
  fi
fi

mkdir -p \
  "${WORKSPACE}" \
  "${WORKSPACE}/.agents" \
  "${WORKSPACE}/tasks" \
  "${WORKSPACE}/artifacts" \
  "${WORKSPACE}/briefs" \
  "${WORKSPACE}/logs"

export PROFILE_DIR
export MARKETINGSKILLS_REPO
export WORKSPACE

python3 - <<'PY'
from pathlib import Path
import os
import sys

try:
    import yaml
except ImportError as exc:
    raise SystemExit(f"PyYAML is required to update Hermes config.yaml: {exc}")

profile_dir = Path(os.environ["PROFILE_DIR"]).expanduser().resolve()
repo = Path(os.environ["MARKETINGSKILLS_REPO"]).expanduser().resolve()
workspace = Path(os.environ["WORKSPACE"]).expanduser().resolve()
config_path = profile_dir / "config.yaml"

def as_int(value, default):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default

cfg = {}
if config_path.exists():
    loaded = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if isinstance(loaded, dict):
        cfg = loaded

cfg.setdefault("skills", {})
existing_dirs = cfg["skills"].get("external_dirs") or []
normalized = []
for entry in [str(repo / "skills"), *existing_dirs]:
    resolved = str(Path(str(entry)).expanduser().resolve())
    if resolved not in normalized:
        normalized.append(resolved)
cfg["skills"]["external_dirs"] = normalized
cfg["skills"]["creation_nudge_interval"] = as_int(
    cfg["skills"].get("creation_nudge_interval"), 15
)

cfg.setdefault("terminal", {})
cfg["terminal"]["backend"] = "local"
cfg["terminal"]["cwd"] = str(workspace)
cfg["terminal"]["timeout"] = max(as_int(cfg["terminal"].get("timeout"), 180), 300)

cfg.setdefault("agent", {})
cfg["agent"]["max_turns"] = max(as_int(cfg["agent"].get("max_turns"), 60), 60)

cfg.setdefault("delegation", {})
cfg["delegation"]["max_iterations"] = max(
    as_int(cfg["delegation"].get("max_iterations"), 30),
    30,
)

config_path.write_text(
    yaml.safe_dump(cfg, sort_keys=False, allow_unicode=False),
    encoding="utf-8",
)
PY

ENV_FILE="${PROFILE_DIR}/.env"
touch "$ENV_FILE"
upsert_env_value "$ENV_FILE" "MARKETINGSKILLS_REPO" "$MARKETINGSKILLS_REPO"
upsert_env_value "$ENV_FILE" "MARKETING_WORKSPACE" "$WORKSPACE"
upsert_env_value "$ENV_FILE" "HERMES_MARKETING_PROFILE" "$PROFILE_NAME"
append_env_block_once "$ENV_FILE"

render_template \
  "${PROJECT_ROOT}/docs/templates/marketingskills-workspace-AGENTS.md.template" \
  "${WORKSPACE}/AGENTS.md"

render_template \
  "${PROJECT_ROOT}/docs/templates/product-marketing-context.md.template" \
  "${WORKSPACE}/.agents/product-marketing-context.md"

cat <<EOF

Hermes marketing profile is ready.

Profile:
  ${PROFILE_NAME}

Profile directory:
  ${PROFILE_DIR}

Marketing skills repo:
  ${MARKETINGSKILLS_REPO}

Workspace:
  ${WORKSPACE}

Next steps:
  1. Fill in ${WORKSPACE}/.agents/product-marketing-context.md
  2. Add the API keys you want in ${ENV_FILE}
  3. Smoke-test the mounted CLIs:
       ${PROJECT_ROOT}/scripts/smoke-test-marketingskills-clis.sh --marketingskills-repo "${MARKETINGSKILLS_REPO}"
  4. Start the profile interactively:
       hermes -p ${PROFILE_NAME}
  5. Or configure messaging + install the gateway service:
       hermes -p ${PROFILE_NAME} gateway setup
       sudo hermes -p ${PROFILE_NAME} gateway install --system --run-as-user "\$USER"
       sudo hermes -p ${PROFILE_NAME} gateway start --system
EOF
