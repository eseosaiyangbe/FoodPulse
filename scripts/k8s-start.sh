#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="foodpulse-dev"
POSTGRES_CLUSTER="foodpulse-postgres"
BUILD_IMAGES=0
RESUME_GITOPS=0
DEPLOYMENTS=(
  foodpulse-api
  foodpulse-ui
)
STATEFULSETS=(
  foodpulse-redis
)
REDIS_ROLLOUT_TIMEOUT="${REDIS_ROLLOUT_TIMEOUT:-600s}"
ARGOCD_NAMESPACE="argocd"
ROOT_APP="internal-developer-platform-dev-root"
APP_NAME="foodpulse-dev"

resume_gitops() {
  echo "[foodpulse-k8s] Re-enabling ArgoCD automated sync for ${ROOT_APP} and ${APP_NAME}"
  kubectl patch application "${ROOT_APP}" -n "${ARGOCD_NAMESPACE}" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
  kubectl patch application "${APP_NAME}" -n "${ARGOCD_NAMESPACE}" --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}' >/dev/null
  kubectl annotate application "${APP_NAME}" -n "${ARGOCD_NAMESPACE}" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

usage() {
  cat <<'EOF'
Usage: ./scripts/k8s-start.sh [options] [-- <extra deploy args>]

Start the FoodPulse dev overlay in the current Kubernetes context.

By default, this reuses existing local images. Use --build when you
intentionally want fresh local image builds.

Options:
  --build      Rebuild images before deploy
  --resume-gitops
               Re-enable ArgoCD automated sync for the platform root and
               foodpulse-dev after workloads are healthy again
  -h, --help   Show this help message
EOF
}

extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD_IMAGES=1
      shift
      ;;
    --resume-gitops)
      RESUME_GITOPS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      extra_args+=("$@")
      break
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

resume_existing_namespace() {
  echo "[foodpulse-k8s] Existing ${NAMESPACE} namespace detected; resuming preserved workloads"
  echo "[foodpulse-k8s] Rehydrating CloudNativePG cluster"
  kubectl annotate cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" \
    -n "${NAMESPACE}" \
    cnpg.io/hibernation- \
    --overwrite >/dev/null 2>&1 || true
  kubectl annotate cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" \
    -n "${NAMESPACE}" \
    cnpg.io/hibernation=off \
    --overwrite

  echo "[foodpulse-k8s] Scaling Redis back up"
  for sts in "${STATEFULSETS[@]}"; do
    kubectl scale statefulset/"${sts}" -n "${NAMESPACE}" --replicas=3
  done

  echo "[foodpulse-k8s] Waiting for PostgreSQL rehydration"
  deadline=$((SECONDS + 600))
  while true; do
    desired_instances="$(kubectl get cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" -n "${NAMESPACE}" -o jsonpath='{.spec.instances}')"
    ready_instances="$(kubectl get cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" -n "${NAMESPACE}" -o jsonpath='{.status.readyInstances}')"
    hibernation_status="$(kubectl get cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="cnpg.io/hibernation")].status}')"
    if [[ -n "${ready_instances}" ]] && [[ "${ready_instances}" == "${desired_instances}" ]] && [[ "${hibernation_status}" != "True" ]]; then
      break
    fi
    if (( SECONDS >= deadline )); then
      echo "[foodpulse-k8s] ERROR: Timed out waiting for PostgreSQL rehydration" >&2
      kubectl get cluster.postgresql.cnpg.io/"${POSTGRES_CLUSTER}" -n "${NAMESPACE}" -o wide >&2 || true
      exit 1
    fi
    sleep 5
  done

  echo "[foodpulse-k8s] Waiting for Redis readiness"
  for sts in "${STATEFULSETS[@]}"; do
    kubectl rollout status statefulset/"${sts}" -n "${NAMESPACE}" --timeout="${REDIS_ROLLOUT_TIMEOUT}"
  done

  echo "[foodpulse-k8s] Scaling application workloads back up"
  for deploy in "${DEPLOYMENTS[@]}"; do
    kubectl scale deployment/"${deploy}" -n "${NAMESPACE}" --replicas=1
  done

  echo "[foodpulse-k8s] Waiting for application rollouts"
  for deploy in "${DEPLOYMENTS[@]}"; do
    kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout=300s
  done

  if [[ "${RESUME_GITOPS}" -eq 1 ]]; then
    resume_gitops
  fi
}

cmd=("${ROOT_DIR}/scripts/k8s-dev-deploy.sh")
if [[ "${BUILD_IMAGES}" -eq 0 ]]; then
  cmd+=(--skip-build)
fi
if [[ "${#extra_args[@]}" -gt 0 ]]; then
  cmd+=("${extra_args[@]}")
fi

if [[ "${BUILD_IMAGES}" -eq 0 ]] && kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  resume_existing_namespace
  exit 0
fi

if [[ "${RESUME_GITOPS}" -eq 1 ]]; then
  echo "[foodpulse-k8s] NOTE: --resume-gitops is ignored during full deploy mode; re-enable automation after the deployment path if needed."
fi

exec "${cmd[@]}"
