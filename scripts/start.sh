#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${HOME}/.zprofile" ]; then
  # Load user-space toolchain paths on this workstation.
  # shellcheck disable=SC1090
  source "${HOME}/.zprofile" >/dev/null 2>&1 || true
fi

export PATH="${HOME}/.local/bin:${HOME}/.docker/cli-plugins:${PATH}"

cd "${REPO_ROOT}"

if [ ! -f .env ]; then
  echo "Missing FoodPulse/.env. Start from .env.example first." >&2
  exit 1
fi

if ! docker network inspect observability-net >/dev/null 2>&1; then
  echo "Creating shared observability-net network..."
  docker network create observability-net >/dev/null
fi

echo "Starting FoodPulse stack..."
docker compose up -d --build --remove-orphans yelb-appserver
docker compose up -d --remove-orphans --force-recreate yelb-ui
docker compose up -d --remove-orphans

echo "FoodPulse is starting."
echo "App: http://localhost:${FOODPULSE_UI_HOST_PORT:-8090}"
