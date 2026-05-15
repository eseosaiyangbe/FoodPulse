#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="foodpulse-dev"
POSTGRES_CLUSTER="foodpulse-postgres"
DEPLOYMENTS=(
  foodpulse-api
  foodpulse-ui
)
STATEFULSETS=(
  foodpulse-redis
)

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-stop.sh [options]

Stop the FoodPulse dev overlay from the current Kubernetes context.
This preserves the namespace and persistent data so the app can be resumed
cleanly with ./scripts/k8s-start.sh.

Options:
  --wait       Wait for scale-down and PostgreSQL hibernation completion
  -h, --help   Show this help message
EOF
}

WAIT_FOR_DELETE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait)
      WAIT_FOR_DELETE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "[foodpulse-k8s] Namespace ${NAMESPACE} does not exist; nothing to stop"
  exit 0
fi

echo "[foodpulse-k8s] Scaling application workloads down"
for deploy in "${DEPLOYMENTS[@]}"; do
  kubectl scale deployment/"${deploy}" -n "${NAMESPACE}" --replicas=0 >/dev/null 2>&1 || true
done

echo "[foodpulse-k8s] Scaling Redis down"
for sts in "${STATEFULSETS[@]}"; do
  kubectl scale statefulset/"${sts}" -n "${NAMESPACE}" --replicas=0 >/dev/null 2>&1 || true
done

echo "[foodpulse-k8s] Hibernating CloudNativePG cluster"
kubectl annotate cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" \
  -n "${NAMESPACE}" \
  cnpg.io/hibernation=on \
  --overwrite

if [[ "${WAIT_FOR_DELETE}" -eq 1 ]]; then
  echo "[foodpulse-k8s] Waiting for workload pods to terminate"
  deadline=$((SECONDS + 600))
  while kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | grep -q .; do
    if (( SECONDS >= deadline )); then
      echo "[foodpulse-k8s] ERROR: Timed out waiting for FoodPulse pods to terminate" >&2
      kubectl get pods -n "${NAMESPACE}" >&2 || true
      exit 1
    fi
    sleep 5
  done

  echo "[foodpulse-k8s] Waiting for PostgreSQL hibernation"
  kubectl wait \
    --namespace "${NAMESPACE}" \
    --for=jsonpath='{.status.conditions[?(@.type=="cnpg.io/hibernation")].status}'=True \
    cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" \
    --timeout=600s
fi
