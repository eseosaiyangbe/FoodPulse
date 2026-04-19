#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${HOME}/.zprofile" ]; then
  # shellcheck disable=SC1090
  source "${HOME}/.zprofile" >/dev/null 2>&1 || true
fi

export PATH="${HOME}/.local/bin:${HOME}/.docker/cli-plugins:${PATH}"

cd "${REPO_ROOT}"

echo "Stopping FoodPulse stack..."
docker compose down --remove-orphans
