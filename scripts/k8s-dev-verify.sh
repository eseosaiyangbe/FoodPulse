#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-dev-verify.sh [options]

Run the FoodPulse k3s dev verification path against the current Kubernetes context.

Options:
  --hostname HOST  Override ingress hostname target (default: foodpulse.devops.local)
  -h, --help       Show this help message
EOF
}

HOSTNAME_OVERRIDE="foodpulse.devops.local"
PORT_FORWARD_PID=""

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $1" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

require_command kubectl
require_command curl

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)
      HOSTNAME_OVERRIDE="${2:?Missing hostname value}"
      shift 2
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

TRAEFIK_ADDR="$(kubectl get ingress -n foodpulse-dev foodpulse -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
if [[ -z "${TRAEFIK_ADDR}" ]]; then
  TRAEFIK_ADDR="$(kubectl get ingress -n foodpulse-dev foodpulse -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
fi

if [[ -z "${TRAEFIK_ADDR}" ]]; then
  echo "ERROR: Could not determine FoodPulse ingress address." >&2
  exit 1
fi

echo "[foodpulse-k8s] Traefik address: ${TRAEFIK_ADDR}"
echo "[foodpulse-k8s] Verifying Kubernetes objects"
kubectl get pods -n foodpulse-dev
kubectl get svc -n foodpulse-dev
kubectl get ingress -n foodpulse-dev

echo "[foodpulse-k8s] Verifying ingress endpoints"
curl -fsS -H "Host: ${HOSTNAME_OVERRIDE}" "http://${TRAEFIK_ADDR}/" >/dev/null
curl -fsS -H "Host: ${HOSTNAME_OVERRIDE}" "http://${TRAEFIK_ADDR}/health" >/dev/null

echo "[foodpulse-k8s] Running end-to-end API validation via port-forward"
kubectl port-forward -n foodpulse-dev svc/foodpulse-api 34567:4567 >/tmp/foodpulse-k8s-port-forward.log 2>&1 &
PORT_FORWARD_PID="$!"
for _ in {1..20}; do
  if curl -fsS http://127.0.0.1:34567/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo
echo "FoodPulse Validation — environment: dev"
echo "Base URL: http://127.0.0.1:34567"
echo "─────────────────────────────────────────"
echo

curl -fsS http://127.0.0.1:34567/health >/dev/null
curl -fsS http://127.0.0.1:34567/metrics | grep -q 'foodpulse_votes_total'

echo "[foodpulse-k8s] Verifying PostgreSQL and Redis"
db_pod="$(kubectl get pods -n foodpulse-dev -l cnpg.io/cluster=foodpulse-postgres,role=primary -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -n foodpulse-dev -c postgres "${db_pod}" -- pg_isready -h 127.0.0.1 -p 5432 -U foodpulse -d foodpulse >/dev/null
kubectl exec -n foodpulse-dev statefulset/foodpulse-redis -c redis -- sh -lc 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli ping | grep -q PONG' >/dev/null
kubectl exec -n foodpulse-dev statefulset/foodpulse-redis -c sentinel -- sh -lc 'redis-cli -p 26379 SENTINEL get-master-addr-by-name foodpulse-cache | grep -q 6379' >/dev/null

echo "[foodpulse-k8s] Verification passed"
