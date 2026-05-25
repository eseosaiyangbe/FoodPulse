#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-foodpulse-dev}"
POD_NAME="${POD_NAME:-foodpulse-state-restore}"
BACKUP_PVC="${BACKUP_PVC:-foodpulse-backup-storage}"
REDIS_PRIMARY_PVC="${REDIS_PRIMARY_PVC:-redis-data-foodpulse-redis-0}"
IMAGE="${IMAGE:-postgres:18-alpine}"
APP_CONFIG="${APP_CONFIG:-foodpulse-app-config}"
POSTGRES_CLUSTER="${POSTGRES_CLUSTER:-foodpulse-postgres}"
POSTGRES_PRIMARY_POD="${POSTGRES_PRIMARY_POD:-}"
POSTGRES_BACKUP_FILE="${1:-}"
REDIS_BACKUP_FILE="${2:-}"

APP_DEPLOYMENTS=(
  foodpulse-api
  foodpulse-ui
)

ORIGINAL_REPLICAS=()

if ! kubectl get pvc -n "${NAMESPACE}" "${BACKUP_PVC}" >/dev/null 2>&1; then
  echo "ERROR: PVC ${BACKUP_PVC} not found in namespace ${NAMESPACE}" >&2
  exit 1
fi

if ! kubectl get pvc -n "${NAMESPACE}" "${REDIS_PRIMARY_PVC}" >/dev/null 2>&1; then
  echo "ERROR: PVC ${REDIS_PRIMARY_PVC} not found in namespace ${NAMESPACE}" >&2
  exit 1
fi

for deployment in "${APP_DEPLOYMENTS[@]}"; do
  ORIGINAL_REPLICAS+=("$(kubectl get deployment -n "${NAMESPACE}" "${deployment}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)")
done
ORIGINAL_REDIS_REPLICAS="$(kubectl get statefulset -n "${NAMESPACE}" foodpulse-redis -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)"

restore_workloads() {
  local index
  local deployment
  local replicas

  kubectl scale statefulset -n "${NAMESPACE}" foodpulse-redis --replicas="${ORIGINAL_REDIS_REPLICAS}" >/dev/null 2>&1 || true

  for index in "${!APP_DEPLOYMENTS[@]}"; do
    deployment="${APP_DEPLOYMENTS[$index]}"
    replicas="${ORIGINAL_REPLICAS[$index]}"
    kubectl scale deployment -n "${NAMESPACE}" "${deployment}" --replicas="${replicas}" >/dev/null 2>&1 || true
  done

  if [[ "${ORIGINAL_REDIS_REPLICAS}" -gt 0 ]]; then
    kubectl rollout status statefulset/foodpulse-redis -n "${NAMESPACE}" --timeout=300s >/dev/null 2>&1 || true
  fi
  for index in "${!APP_DEPLOYMENTS[@]}"; do
    deployment="${APP_DEPLOYMENTS[$index]}"
    replicas="${ORIGINAL_REPLICAS[$index]}"
    if [[ "${replicas}" -gt 0 ]]; then
      kubectl rollout status deployment/"${deployment}" -n "${NAMESPACE}" --timeout=300s >/dev/null 2>&1 || true
    fi
  done
}

wait_for_zero_pods() {
  local namespace="$1"
  local selector="$2"
  for _ in $(seq 1 180); do
    local count
    count="$(kubectl get pods -n "${namespace}" -l "${selector}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${count}" = "0" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: Timed out waiting for pods with selector ${selector} to terminate" >&2
  return 1
}

trap 'restore_workloads; kubectl delete pod -n "${NAMESPACE}" "${POD_NAME}" --ignore-not-found >/dev/null 2>&1 || true' EXIT

for deployment in "${APP_DEPLOYMENTS[@]}"; do
  kubectl scale deployment -n "${NAMESPACE}" "${deployment}" --replicas=0 >/dev/null
done
kubectl scale statefulset -n "${NAMESPACE}" foodpulse-redis --replicas=0 >/dev/null

wait_for_zero_pods "${NAMESPACE}" "app.kubernetes.io/name=foodpulse-api"
wait_for_zero_pods "${NAMESPACE}" "app.kubernetes.io/name=foodpulse-ui"
wait_for_zero_pods "${NAMESPACE}" "app.kubernetes.io/name=foodpulse-redis"

kubectl delete pod -n "${NAMESPACE}" "${POD_NAME}" --ignore-not-found >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    backup-role: state-backup
spec:
  restartPolicy: Never
  containers:
    - name: restore
      image: ${IMAGE}
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 250m
          memory: 256Mi
      command:
        - /bin/sh
        - -ec
        - sleep 3600
      volumeMounts:
        - name: backup-storage
          mountPath: /backup
        - name: redis-primary-storage
          mountPath: /redis-primary
  volumes:
    - name: backup-storage
      persistentVolumeClaim:
        claimName: ${BACKUP_PVC}
    - name: redis-primary-storage
      persistentVolumeClaim:
        claimName: ${REDIS_PRIMARY_PVC}
EOF

for _ in $(seq 1 60); do
  if kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" >/dev/null 2>&1; then
  echo "ERROR: restore pod ${POD_NAME} was not created" >&2
  exit 1
fi

for _ in $(seq 1 180); do
  phase="$(kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "${phase}" = "Running" ]]; then
    break
  fi
  sleep 1
done

phase="$(kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "${phase}" != "Running" ]]; then
  echo "ERROR: restore pod ${POD_NAME} did not reach Running phase" >&2
  kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" -o wide || true
  exit 1
fi

if [[ -z "${POSTGRES_PRIMARY_POD}" ]]; then
  POSTGRES_PRIMARY_POD="$(kubectl get cluster -n "${NAMESPACE}" "${POSTGRES_CLUSTER}" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
fi

if [[ -z "${POSTGRES_PRIMARY_POD}" ]]; then
  echo "ERROR: could not determine current PostgreSQL primary pod from cluster ${POSTGRES_CLUSTER}" >&2
  exit 1
fi

PGDATABASE="$(kubectl get configmap -n "${NAMESPACE}" "${APP_CONFIG}" -o jsonpath='{.data.FOODPULSE_DB_NAME}')"

postgres_backup_path="${POSTGRES_BACKUP_FILE}"
if [[ -z "${postgres_backup_path}" ]]; then
  postgres_backup_path="$(kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- sh -lc "find /backup -maxdepth 1 -type f -name 'foodpulse-postgres-*.dump' -size +0c | sort | tail -n 1")"
elif [[ "${postgres_backup_path}" != /* ]]; then
  postgres_backup_path="/backup/${postgres_backup_path}"
fi

redis_backup_path="${REDIS_BACKUP_FILE}"
if [[ -z "${redis_backup_path}" ]]; then
  redis_backup_path="$(kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- sh -lc "find /backup -maxdepth 1 -type f -name 'foodpulse-redis-*.rdb' -size +0c | sort | tail -n 1")"
elif [[ "${redis_backup_path}" != /* ]]; then
  redis_backup_path="/backup/${redis_backup_path}"
fi

if [[ -z "${postgres_backup_path}" ]]; then
  echo "ERROR: could not resolve PostgreSQL backup file" >&2
  exit 1
fi

if [[ -z "${redis_backup_path}" ]]; then
  echo "ERROR: could not resolve Redis backup file" >&2
  exit 1
fi

kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- sh -lc "[ -f '${postgres_backup_path}' ]"
kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- sh -lc "[ -f '${redis_backup_path}' ]"

echo "Waiting for PostgreSQL local superuser path on pod ${POSTGRES_PRIMARY_POD}"
for _ in $(seq 1 60); do
  if kubectl exec -n "${NAMESPACE}" "${POSTGRES_PRIMARY_POD}" -- sh -lc "psql -U postgres -d '${PGDATABASE}' -Atc 'select 1'" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "Restoring PostgreSQL backup ${postgres_backup_path} through local superuser on ${POSTGRES_PRIMARY_POD}"
kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- cat "${postgres_backup_path}" | \
  kubectl exec -i -n "${NAMESPACE}" "${POSTGRES_PRIMARY_POD}" -- sh -lc "pg_restore --username=postgres --dbname='${PGDATABASE}' --clean --if-exists --no-owner --no-privileges --exit-on-error"

echo "Restoring Redis primary backup ${redis_backup_path}"
kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- sh -ec "
  rm -rf /redis-primary/* /redis-primary/.[!.]* /redis-primary/..?* 2>/dev/null || true
  cp '${redis_backup_path}' /redis-primary/dump.rdb
  rm -rf /redis-primary/appendonlydir 2>/dev/null || true
  ls -lh /redis-primary
"

echo "Restore completed from ${postgres_backup_path} and ${redis_backup_path}"
