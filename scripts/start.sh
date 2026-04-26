#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/start.sh [options]

Start the local FoodPulse stack.

Options:
  --build      Force an image rebuild before startup
  -h, --help   Show this help message
EOF
}

if [ -f "${HOME}/.zprofile" ]; then
  # Load user-space toolchain paths on this workstation.
  # shellcheck disable=SC1090
  source "${HOME}/.zprofile" >/dev/null 2>&1 || true
fi

export PATH="${HOME}/.local/bin:${HOME}/.docker/cli-plugins:${PATH}"

cd "${REPO_ROOT}"

force_build=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      force_build=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ ! -f .env ]; then
  echo "Missing FoodPulse/.env. Start from .env.example first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source ./.env
set +a

: "${FOODPULSE_DB_SERVER:=pg-haproxy}"
: "${FOODPULSE_DB_NAME:=foodpulse}"
: "${FOODPULSE_DB_USER:=foodpulse}"
: "${FOODPULSE_DB_PASSWORD:=change-me}"
: "${FOODPULSE_REDIS_SERVER:=redis-haproxy}"
: "${FOODPULSE_REDIS_PASSWORD:=admin}"

export FOODPULSE_DB_SERVER FOODPULSE_DB_NAME FOODPULSE_DB_USER FOODPULSE_DB_PASSWORD
export FOODPULSE_REDIS_SERVER FOODPULSE_REDIS_PASSWORD

if ! docker network inspect observability-net >/dev/null 2>&1; then
  echo "Creating shared observability-net network..."
  docker network create observability-net >/dev/null
fi

echo "Starting FoodPulse stack..."
if [[ "${force_build}" -eq 1 ]]; then
  docker compose up -d --build --remove-orphans
else
  docker compose up -d --remove-orphans
fi

echo "FoodPulse is starting."
echo "App: http://localhost:${FOODPULSE_UI_HOST_PORT:-8090}"
