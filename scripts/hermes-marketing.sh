#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="${HERMES_MARKETING_PROFILE:-marketing}"

exec hermes -p "${PROFILE_NAME}" "$@"
