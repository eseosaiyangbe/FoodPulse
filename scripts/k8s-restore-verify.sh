#!/usr/bin/env sh
set -eu

NAMESPACE="${NAMESPACE:-foodpulse-dev}"
POD_NAME="${POD_NAME:-foodpulse-restore-verify}"
REDIS_PRIMARY_PVC="${REDIS_PRIMARY_PVC:-redis-data-foodpulse-redis-0}"
IMAGE="${IMAGE:-postgres:18-alpine}"
POSTGRES_SECRET="${POSTGRES_SECRET:-foodpulse-postgres-app}"
APP_CONFIG="${APP_CONFIG:-foodpulse-app-config}"
POSTGRES_HOST="${POSTGRES_HOST:-foodpulse-postgres-rw}"

kubectl rollout status deployment/foodpulse-api -n "${NAMESPACE}" --timeout=300s >/dev/null
kubectl rollout status deployment/foodpulse-ui -n "${NAMESPACE}" --timeout=300s >/dev/null
kubectl rollout status statefulset/foodpulse-redis -n "${NAMESPACE}" --timeout=300s >/dev/null

if ! kubectl get pvc -n "${NAMESPACE}" "${REDIS_PRIMARY_PVC}" >/dev/null 2>&1; then
  echo "ERROR: PVC ${REDIS_PRIMARY_PVC} not found in namespace ${NAMESPACE}" >&2
  exit 1
fi

kubectl delete pod -n "${NAMESPACE}" "${POD_NAME}" --ignore-not-found >/dev/null 2>&1 || true
trap 'kubectl delete pod -n "${NAMESPACE}" "${POD_NAME}" --ignore-not-found >/dev/null 2>&1 || true' EXIT

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
    - name: verify
      image: ${IMAGE}
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          cpu: 25m
          memory: 64Mi
        limits:
          cpu: 150m
          memory: 128Mi
      env:
        - name: PGHOST
          value: ${POSTGRES_HOST}
        - name: PGPORT
          valueFrom:
            configMapKeyRef:
              name: ${APP_CONFIG}
              key: FOODPULSE_DB_PORT
        - name: PGUSER
          valueFrom:
            secretKeyRef:
              name: ${POSTGRES_SECRET}
              key: username
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: ${POSTGRES_SECRET}
              key: password
        - name: PGDATABASE
          valueFrom:
            configMapKeyRef:
              name: ${APP_CONFIG}
              key: FOODPULSE_DB_NAME
      command:
        - /bin/sh
        - -ec
        - |
          echo "Waiting for PostgreSQL at \${PGHOST}:\${PGPORT}"
          for _ in \$(seq 1 60); do
            if pg_isready -h "\${PGHOST}" -p "\${PGPORT}" -U "\${PGUSER}" -d "\${PGDATABASE}" >/dev/null 2>&1; then
              break
            fi
            sleep 2
          done

          echo "Verifying PostgreSQL restore state"
          psql -h "\${PGHOST}" -p "\${PGPORT}" -U "\${PGUSER}" -d "\${PGDATABASE}" -v ON_ERROR_STOP=1 -c "
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'public'
              AND tablename IN ('venues', 'vote_events')
            ORDER BY tablename;
          "

          psql -h "\${PGHOST}" -p "\${PGPORT}" -U "\${PGUSER}" -d "\${PGDATABASE}" -v ON_ERROR_STOP=1 -c "
            SELECT
              (SELECT COUNT(*) FROM venues) AS venues,
              (SELECT COUNT(*) FROM vote_events) AS vote_events;
          "

          echo "Verifying Redis primary PVC data files"
          if [ ! -f /redis-primary/dump.rdb ]; then
            echo "ERROR: Redis dump.rdb not present on restored PVC" >&2
            exit 1
          fi
          find /redis-primary -maxdepth 2 -type f | sort
      volumeMounts:
        - name: redis-primary-storage
          mountPath: /redis-primary
  volumes:
    - name: redis-primary-storage
      persistentVolumeClaim:
        claimName: ${REDIS_PRIMARY_PVC}
EOF

for _ in $(seq 1 180); do
  phase="$(kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "${phase}" = "Succeeded" ] || [ "${phase}" = "Failed" ]; then
    break
  fi
  sleep 1
done

kubectl logs -n "${NAMESPACE}" "${POD_NAME}"
phase="$(kubectl get pod -n "${NAMESPACE}" "${POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [ "${phase}" != "Succeeded" ]; then
  echo "ERROR: restore verification pod ended in phase ${phase:-Unknown}" >&2
  exit 1
fi
