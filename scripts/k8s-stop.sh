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
SUSPEND_GITOPS=0
ARGOCD_NAMESPACE="argocd"
ROOT_APP="internal-developer-platform-dev-root"
APP_NAME="foodpulse-dev"

gitops_automated_enabled() {
  local app="$1"
  local prune
  local self_heal

  prune="$(kubectl get application "${app}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.spec.syncPolicy.automated.prune}' 2>/dev/null || true)"
  self_heal="$(kubectl get application "${app}" -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null || true)"

  [[ "${prune}" == "true" || "${self_heal}" == "true" ]]
}

suspend_gitops() {
  echo "[foodpulse-k8s] Suspending ArgoCD automated sync for ${ROOT_APP} and ${APP_NAME}"
  kubectl patch application "${ROOT_APP}" -n "${ARGOCD_NAMESPACE}" --type json \
    -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]' >/dev/null 2>&1 || true
  kubectl patch application "${APP_NAME}" -n "${ARGOCD_NAMESPACE}" --type json \
    -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]' >/dev/null 2>&1 || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait)
      WAIT_FOR_DELETE=1
      shift
      ;;
    --suspend-gitops)
      SUSPEND_GITOPS=1
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

if [[ "${SUSPEND_GITOPS}" -eq 1 ]]; then
  suspend_gitops
elif gitops_automated_enabled "${ROOT_APP}" || gitops_automated_enabled "${APP_NAME}"; then
  echo "[foodpulse-k8s] ERROR: ArgoCD automated sync is still enabled for ${ROOT_APP} or ${APP_NAME}" >&2
  echo "[foodpulse-k8s] Refusing to stop preserved workloads while GitOps can reconcile them back up." >&2
  echo "[foodpulse-k8s] Re-run with --suspend-gitops, or suspend sync first with:" >&2
  echo "  kubectl patch application ${ROOT_APP} -n ${ARGOCD_NAMESPACE} --type json -p='[{\"op\":\"remove\",\"path\":\"/spec/syncPolicy/automated\"}]'" >&2
  echo "  kubectl patch application ${APP_NAME} -n ${ARGOCD_NAMESPACE} --type json -p='[{\"op\":\"remove\",\"path\":\"/spec/syncPolicy/automated\"}]'" >&2
  exit 1
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
