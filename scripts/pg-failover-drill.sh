#!/usr/bin/env bash
set -u  # do NOT use -e; we want the script to continue on errors

# ------------ Load env ------------
# Adjust if your path changes; this matches your Redis drill convention
ENV_FILE="${ENV_FILE:-../.env}"

if [ -f "${ENV_FILE}" ]; then
  echo "Loading environment from ${ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
set -u  # do NOT use -e; we want the script to continue on errors

# ------------ Load env ------------
# Adjust if your path changes; this matches your Redis drill convention
ENV_FILE="${ENV_FILE:-../.env}"

if [ -f "${ENV_FILE}" ]; then
  echo "Loading environment from ${ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
else
  echo "WARN: ${ENV_FILE} not found, falling back to defaults."
fi

# ------------ Config ------------
PG_PRIMARY_CONTAINER="${PG_PRIMARY_CONTAINER:-yelb-db}"
PG_REPLICA1_CONTAINER="${PG_REPLICA1_CONTAINER:-yelb-db-replica1}"
PG_REPLICA2_CONTAINER="${PG_REPLICA2_CONTAINER:-yelb-db-replica2}"
PG_REPLICA3_CONTAINER="${PG_REPLICA3_CONTAINER:-yelb-db-replica3}"
PG_HAPROXY_CONTAINER="${PG_HAPROXY_CONTAINER:-pg-haproxy}"

PG_USER="${YELB_DB_USER:-postgres}"
PG_PASSWORD="${YELB_DB_PASSWORD:-postgres_password}"
PG_DB="${PG_DB:-postgres}"

# Figure out the Docker network name attached to pg-haproxy
NETWORK_NAME="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "${PG_HAPROXY_CONTAINER}" 2>/dev/null || true)"

echo "=== POSTGRES FAILOVER DRILL ==="
echo "Timestamp: $(date)"
echo "Using Docker network: ${NETWORK_NAME:-UNKNOWN}"
echo

# ------------ Helpers ------------

pg_role_cmd() {
  local container="$1"
  docker exec -e PGPASSWORD="${PG_PASSWORD}" -it "${container}" \
    psql -U "${PG_USER}" -d "${PG_DB}" -tAc \
      "SELECT inet_server_addr(), pg_is_in_recovery();" \
    || echo "  [WARN] could not query ${container}"
}

pg_role_cmd_haproxy_rw() {
  if [ -z "${NETWORK_NAME}" ]; then
    echo "  [WARN] NETWORK_NAME is empty; cannot query via pg-haproxy RW (5432)"
    return 0
  fi

  docker run --rm -i \
    --network "${NETWORK_NAME}" \
    postgres:14 \
    env PGPASSWORD="${PG_PASSWORD}" \
    psql -h pg-haproxy -p 5432 -U "${PG_USER}" -d "${PG_DB}" -tAc \
      "SELECT inet_server_addr(), pg_is_in_recovery();" \
    || echo "  [WARN] could not query via pg-haproxy RW (5432)"
}

pg_role_cmd_haproxy_ro() {
  if [ -z "${NETWORK_NAME}" ]; then
    echo "  [WARN] NETWORK_NAME is empty; cannot query via pg-haproxy RO (5433)"
    return 0
  fi

  docker run --rm -i \
    --network "${NETWORK_NAME}" \
    postgres:14 \
    env PGPASSWORD="${PG_PASSWORD}" \
    psql -h pg-haproxy -p 5433 -U "${PG_USER}" -d "${PG_DB}" -tAc \
      "SELECT inet_server_addr(), pg_is_in_recovery();" \
    || echo "  [WARN] could not query via pg-haproxy RO (5433)"
}

# ------------ Drill steps ------------

echo "1) Current roles (direct containers)"
echo "------------------------------------"
echo "Primary candidate (${PG_PRIMARY_CONTAINER}):"
pg_role_cmd "${PG_PRIMARY_CONTAINER}"
echo
echo "Replica 1 (${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "2) What HAProxy (pg-haproxy) currently routes to"
echo "-----------------------------------------------"
echo "RW pool (5432):"
pg_role_cmd_haproxy_rw
echo
echo "RO pool (5433):"
pg_role_cmd_haproxy_ro
echo

read -r -p ">>> Press ENTER to STOP current primary (${PG_PRIMARY_CONTAINER}) and simulate failure..." _

echo
echo "3) Stopping current primary: ${PG_PRIMARY_CONTAINER}"
echo "----------------------------------------------------"
docker stop "${PG_PRIMARY_CONTAINER}"
echo "Waiting 10s for HAProxy health-checks to mark it down..."
sleep 10
echo

echo "4) Roles AFTER primary is down (direct containers)"
echo "--------------------------------------------------"
echo "Replica 1 (${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "5) HAProxy view AFTER primary is down"
echo "-------------------------------------"
echo "RW pool (5432):"
pg_role_cmd_haproxy_rw
echo
echo "RO pool (5433):"
pg_role_cmd_haproxy_ro
echo

read -r -p ">>> Press ENTER to PROMOTE ${PG_REPLICA1_CONTAINER} to primary using pg_promote() (lab-only, will break original replication topology)..." _

echo
echo "6) Promoting ${PG_REPLICA1_CONTAINER} to PRIMARY using pg_promote()"
echo "------------------------------------------------------------------"
docker exec -e PGPASSWORD="${PG_PASSWORD}" -it "${PG_REPLICA1_CONTAINER}" \
  psql -U "${PG_USER}" -d "${PG_DB}" -c "SELECT pg_promote();" \
  || echo "  [WARN] pg_promote() failed on ${PG_REPLICA1_CONTAINER}"
echo "Waiting 10s for promotion to complete..."
sleep 10
echo

echo "7) Roles AFTER promotion (direct containers)"
echo "--------------------------------------------"
echo "Old primary (${PG_PRIMARY_CONTAINER}) – currently STOPPED."
echo
echo "Replica 1 (promoted: ${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "8) HAProxy view AFTER promotion"
echo "--------------------------------"
echo "RW pool (5432):"
pg_role_cmd_haproxy_rw
echo
echo "RO pool (5433):"
pg_role_cmd_haproxy_ro
echo

read -r -p ">>> Press ENTER to START old primary (${PG_PRIMARY_CONTAINER}) again (it will NOT automatically become a replica)..." _

docker start "${PG_PRIMARY_CONTAINER}"
echo "Waiting 10s for it to come up..."
sleep 10
echo

echo "9) Final roles AFTER old primary returns"
echo "----------------------------------------"
echo "Old primary (${PG_PRIMARY_CONTAINER}):"
pg_role_cmd "${PG_PRIMARY_CONTAINER}"
echo
echo "Promoted node (${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "10) Final HAProxy view"
echo "----------------------"
echo "RW pool (5432):"
pg_role_cmd_haproxy_rw
echo
echo "RO pool (5433):"
pg_role_cmd_haproxy_ro
echo

cat <<'EOF'

NOTE:
- This drill shows connectivity and manual promotion only.
- After promoting yelb-db-replica1, your replication topology is no longer "clean":
  * The old primary (yelb-db) is now an independent Postgres instance.
  * Other replicas may still be following the old primary or be out-of-date.
- In a real production environment you would use a proper HA stack
  (Patroni, repmgr, Stolon, etc.) to:
    * Detect failure,
    * Promote a new primary,
    * Re-seed and re-point replicas automatically.

=== POSTGRES FAILOVER DRILL COMPLETE ===
EOF

  set +a
else
  echo "WARN: ${ENV_FILE} not found, falling back to defaults."
fi

# ------------ Config ------------
PG_PRIMARY_CONTAINER="${PG_PRIMARY_CONTAINER:-yelb-db}"
PG_REPLICA1_CONTAINER="${PG_REPLICA1_CONTAINER:-yelb-db-replica1}"
PG_REPLICA2_CONTAINER="${PG_REPLICA2_CONTAINER:-yelb-db-replica2}"
PG_REPLICA3_CONTAINER="${PG_REPLICA3_CONTAINER:-yelb-db-replica3}"
PG_HAPROXY_CONTAINER="${PG_HAPROXY_CONTAINER:-pg-haproxy}"

PG_USER="${YELB_DB_USER:-postgres}"
PG_PASSWORD="${YELB_DB_PASSWORD:-postgres_password}"
PG_DB="${PG_DB:-postgres}"

# Figure out the Docker network name attached to pg-haproxy
NETWORK_NAME="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "${PG_HAPROXY_CONTAINER}" 2>/dev/null || true)"

echo "=== POSTGRES FAILOVER DRILL ==="
echo "Timestamp: $(date)"
echo "Using Docker network: ${NETWORK_NAME:-UNKNOWN}"
echo

pg_role_cmd() {
  local container="$1"
  docker exec -e PGPASSWORD="${PG_PASSWORD}" -it "${container}" \
    psql -U "${PG_USER}" -d "${PG_DB}" -tAc "SELECT inet_server_addr(), pg_is_in_recovery();" \
    || echo "  [WARN] could not query ${container}"
}

pg_role_cmd_haproxy() {
  docker run --rm -i \
    --network "${NETWORK_NAME}" \
    postgres:14 \
    env PGPASSWORD="${PG_PASSWORD}" \
    psql -h pg-haproxy -U "${PG_USER}" -d "${PG_DB}" -tAc \
      "SELECT inet_server_addr(), pg_is_in_recovery();" \
    || echo "  [WARN] could not query via pg-haproxy"
}

echo "1) Current roles (direct containers)"
echo "------------------------------------"
echo "Primary candidate (${PG_PRIMARY_CONTAINER}):"
pg_role_cmd "${PG_PRIMARY_CONTAINER}"
echo
echo "Replica 1 (${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "2) What HAProxy (pg-haproxy) currently routes to"
echo "-----------------------------------------------"
pg_role_cmd_haproxy
echo

read -r -p ">>> Press ENTER to STOP current primary (${PG_PRIMARY_CONTAINER}) and simulate failure..." _

echo
echo "3) Stopping current primary: ${PG_PRIMARY_CONTAINER}"
echo "----------------------------------------------------"
docker stop "${PG_PRIMARY_CONTAINER}"
echo "Waiting 10s for HAProxy health-checks to mark it down..."
sleep 10
echo

echo "4) Roles AFTER primary is down (direct containers)"
echo "--------------------------------------------------"
echo "Replica 1 (${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "5) HAProxy view AFTER primary is down"
echo "-------------------------------------"
pg_role_cmd_haproxy
echo

read -r -p ">>> Press ENTER to PROMOTE ${PG_REPLICA1_CONTAINER} to primary using pg_promote() (lab-only, will break original replication topology)..." _

echo
echo "6) Promoting ${PG_REPLICA1_CONTAINER} to PRIMARY using pg_promote()"
echo "------------------------------------------------------------------"
docker exec -e PGPASSWORD="${PG_PASSWORD}" -it "${PG_REPLICA1_CONTAINER}" \
  psql -U "${PG_USER}" -d "${PG_DB}" -c "SELECT pg_promote();" \
  || echo "  [WARN] pg_promote() failed on ${PG_REPLICA1_CONTAINER}"
echo "Waiting 10s for promotion to complete..."
sleep 10
echo

echo "7) Roles AFTER promotion (direct containers)"
echo "--------------------------------------------"
echo "Old primary (${PG_PRIMARY_CONTAINER}) – currently STOPPED."
echo
echo "Replica 1 (promoted: ${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "8) HAProxy view AFTER promotion"
echo "--------------------------------"
pg_role_cmd_haproxy
echo

read -r -p ">>> Press ENTER to START old primary (${PG_PRIMARY_CONTAINER}) again (it will NOT automatically become a replica)..." _

docker start "${PG_PRIMARY_CONTAINER}"
echo "Waiting 10s for it to come up..."
sleep 10
echo

echo "9) Final roles AFTER old primary returns"
echo "----------------------------------------"
echo "Old primary (${PG_PRIMARY_CONTAINER}):"
pg_role_cmd "${PG_PRIMARY_CONTAINER}"
echo
echo "Promoted node (${PG_REPLICA1_CONTAINER}):"
pg_role_cmd "${PG_REPLICA1_CONTAINER}"
echo
echo "Replica 2 (${PG_REPLICA2_CONTAINER}):"
pg_role_cmd "${PG_REPLICA2_CONTAINER}"
echo
echo "Replica 3 (${PG_REPLICA3_CONTAINER}):"
pg_role_cmd "${PG_REPLICA3_CONTAINER}"
echo

echo "10) Final HAProxy view"
echo "----------------------"
pg_role_cmd_haproxy
echo

cat <<'EOF'

NOTE:
- This drill shows connectivity and manual promotion only.
- After promoting yelb-db-replica1, your replication topology is no longer "clean":
  * The old primary (yelb-db) is now an independent Postgres instance.
  * Other replicas may still be following the old primary or be out-of-date.
- In a real production environment you would use a proper HA stack
  (Patroni, repmgr, Stolon, etc.) to:
    * Detect failure,
    * Promote a new primary,
    * Re-seed and re-point replicas automatically.

=== POSTGRES FAILOVER DRILL COMPLETE ===
EOF
