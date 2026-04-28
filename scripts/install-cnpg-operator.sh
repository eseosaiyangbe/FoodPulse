#!/usr/bin/env bash
set -euo pipefail

CNPG_VERSION="${CNPG_VERSION:-1.29.0}"
CNPG_RELEASE_URL="https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-${CNPG_VERSION}.yaml"

if kubectl get deployment cnpg-controller-manager -n cnpg-system >/dev/null 2>&1; then
  echo "[foodpulse-k8s] CloudNativePG operator already present"
else
  echo "[foodpulse-k8s] Installing CloudNativePG operator ${CNPG_VERSION}"
  kubectl apply --server-side -f "${CNPG_RELEASE_URL}"
fi

kubectl rollout status deployment/cnpg-controller-manager -n cnpg-system --timeout=240s >/dev/null
echo "[foodpulse-k8s] CloudNativePG operator ready"
