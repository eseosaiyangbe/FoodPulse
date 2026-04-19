#!/usr/bin/env bash
# redis-failover-drill.sh
set -u  # do NOT use -e; we want to see failures and keep going

# ------------ Locate and load .env ------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default: project-root/.env (one level up from scripts/)
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/../.env}"

if [ -f "${ENV_FILE}" ]; then
  echo "Loading environment from ${ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
else
  echo "WARN: ${ENV_FILE} not found, falling back to hard-coded password 'admin'."
fi

# ------------ Config ------------
REDIS_MASTER_CONTAINER="redis-server"
REDIS_REPLICA1_CONTAINER="odilia-redis01"
REDIS_REPLICA2_CONTAINER="odilia-redis02"
REDIS_HAPROXY_CONTAINER="redis-haproxy"

# Take from env if set, else default to 'admin'
REDIS_PASSWORD="${YELB_REDIS_PASSWORD:-admin}"

echo "=== REDIS FAILOVER DRILL ==="
echo "Timestamp: $(date)"
echo

# Derive the Docker network *name* redis-haproxy is attached to
REDIS_NETWORK="$(docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{ $name }}{{end}}' "${REDIS_HAPROXY_CONTAINER}")"

echo "Using Docker network: ${REDIS_NETWORK}"
echo

echo "1) Current replication roles (direct containers)"
echo "------------------------------------------------"
docker exec -it "${REDIS_MASTER_CONTAINER}"  redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] master check failed"
docker exec -it "${REDIS_REPLICA1_CONTAINER}" redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] replica1 check failed"
docker exec -it "${REDIS_REPLICA2_CONTAINER}" redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] replica2 check failed"
echo

echo "2) What HAProxy (redis-haproxy) sees as master"
echo "----------------------------------------------"
docker run --rm -i \
  --network "${REDIS_NETWORK}" \
  redis:7.2 \
  redis-cli -h redis-haproxy -p 6379 -a "${REDIS_PASSWORD}" \
    INFO replication | egrep 'role|master_host' || echo "  [WARN] HAProxy view failed"
echo

read -r -p ">>> Press ENTER to STOP current Redis master (${REDIS_MASTER_CONTAINER}) and trigger failover..." _

echo
echo "3) Stopping current master: ${REDIS_MASTER_CONTAINER}"
echo "------------------------------------------------------"
docker stop "${REDIS_MASTER_CONTAINER}"
echo "Waiting 15s for Sentinel failover..."
sleep 15
echo

echo "4) Roles AFTER failover (direct containers)"
echo "-------------------------------------------"
docker exec -it "${REDIS_REPLICA1_CONTAINER}" redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] replica1 check failed"
docker exec -it "${REDIS_REPLICA2_CONTAINER}" redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] replica2 check failed"
echo

echo "5) HAProxy view AFTER failover"
echo "-------------------------------"
docker run --rm -i \
  --network "${REDIS_NETWORK}" \
  redis:7.2 \
  redis-cli -h redis-haproxy -p 6379 -a "${REDIS_PASSWORD}" \
    INFO replication | egrep 'role|master_host' || echo "  [WARN] HAProxy view failed"
echo

read -r -p ">>> Press ENTER to START old master (${REDIS_MASTER_CONTAINER}) back up (it should rejoin as replica)..." _

echo
docker start "${REDIS_MASTER_CONTAINER}"
echo "Waiting 10s for it to register with Sentinel..."
sleep 10
echo

echo "6) Final roles AFTER old master returns"
echo "---------------------------------------"
docker exec -it "${REDIS_MASTER_CONTAINER}"  redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] master container check failed"
docker exec -it "${REDIS_REPLICA1_CONTAINER}" redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] replica1 check failed"
docker exec -it "${REDIS_REPLICA2_CONTAINER}" redis-cli -a "${REDIS_PASSWORD}" INFO replication | egrep 'role|master_host' || echo "  [WARN] replica2 check failed"
echo

echo "7) HAProxy final view"
echo "----------------------"
docker run --rm -i \
  --network "${REDIS_NETWORK}" \
  redis:7.2 \
  redis-cli -h redis-haproxy -p 6379 -a "${REDIS_PASSWORD}" \
    INFO replication | egrep 'role|master_host' || echo "  [WARN] HAProxy final view failed"
echo

echo "=== REDIS FAILOVER DRILL COMPLETE ==="
