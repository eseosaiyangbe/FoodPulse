#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-dev-destroy.sh

Delete the FoodPulse k3s dev overlay from the current Kubernetes context.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

echo "[foodpulse-k8s] Deleting overlay"
kubectl delete -k k8s/overlays/dev --ignore-not-found=true
