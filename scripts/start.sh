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

set -a
# shellcheck disable=SC1091
source ./.env
set +a

: "${FOODPULSE_DB_SERVER:=${YELB_DB_SERVER:-pg-haproxy}}"
: "${FOODPULSE_DB_NAME:=${YELB_DB_NAME:-foodpulse}}"
: "${FOODPULSE_DB_USER:=${YELB_DB_USER:-foodpulse}}"
: "${FOODPULSE_DB_PASSWORD:=${YELB_DB_PASSWORD:-change-me}}"
: "${FOODPULSE_REDIS_SERVER:=${YELB_REDIS_SERVER:-redis-haproxy}}"
: "${FOODPULSE_REDIS_PASSWORD:=${YELB_REDIS_PASSWORD:-admin}}"

: "${YELB_DB_SERVER:=${FOODPULSE_DB_SERVER}}"
: "${YELB_DB_NAME:=${FOODPULSE_DB_NAME}}"
: "${YELB_DB_USER:=${FOODPULSE_DB_USER}}"
: "${YELB_DB_PASSWORD:=${FOODPULSE_DB_PASSWORD}}"
: "${YELB_REDIS_SERVER:=${FOODPULSE_REDIS_SERVER}}"
: "${YELB_REDIS_PASSWORD:=${FOODPULSE_REDIS_PASSWORD}}"

export FOODPULSE_DB_SERVER FOODPULSE_DB_NAME FOODPULSE_DB_USER FOODPULSE_DB_PASSWORD
export FOODPULSE_REDIS_SERVER FOODPULSE_REDIS_PASSWORD
export YELB_DB_SERVER YELB_DB_NAME YELB_DB_USER YELB_DB_PASSWORD
export YELB_REDIS_SERVER YELB_REDIS_PASSWORD

if ! docker network inspect observability-net >/dev/null 2>&1; then
  echo "Creating shared observability-net network..."
  docker network create observability-net >/dev/null
fi

echo "Starting FoodPulse stack..."
docker compose up -d --build --remove-orphans foodpulse-appserver foodpulse-ui
docker compose up -d --remove-orphans --force-recreate foodpulse-ui
docker compose up -d --remove-orphans

echo "FoodPulse is starting."
echo "App: http://localhost:${FOODPULSE_UI_HOST_PORT:-8090}"
