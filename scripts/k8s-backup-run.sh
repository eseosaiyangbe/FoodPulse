#!/usr/bin/env sh
set -eu

NAMESPACE="${NAMESPACE:-foodpulse-dev}"
CRONJOB_NAME="${CRONJOB_NAME:-foodpulse-state-backup}"
JOB_NAME="${JOB_NAME:-foodpulse-state-backup-manual}"

kubectl delete job -n "${NAMESPACE}" "${JOB_NAME}" --ignore-not-found >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
  if ! kubectl get job -n "${NAMESPACE}" "${JOB_NAME}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
kubectl create job -n "${NAMESPACE}" --from=cronjob/"${CRONJOB_NAME}" "${JOB_NAME}"
kubectl wait --for=condition=complete job/"${JOB_NAME}" -n "${NAMESPACE}" --timeout=600s

pod_name="$(kubectl get pods -n "${NAMESPACE}" -l job-name="${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}')"

kubectl logs -n "${NAMESPACE}" "${pod_name}" -c postgres-backup
kubectl logs -n "${NAMESPACE}" "${pod_name}" -c redis-backup
