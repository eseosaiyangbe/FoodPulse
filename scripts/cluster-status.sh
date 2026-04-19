#!/usr/bin/env bash
# Cluster status dashboard for the FoodPulse HA stack
# Redis + Postgres + HAProxy + App
# Exits non-zero if degraded.

# Do NOT use -e; we want partial output even if some checks fail
set -u

if [ -f "$HOME/.zprofile" ]; then
  # The workstation bootstrap installs Docker in user-space locations on macOS.
  # shellcheck source=/dev/null
  . "$HOME/.zprofile" >/dev/null 2>&1 || true
fi

export PATH="$HOME/.local/bin:$HOME/.docker/cli-plugins:$PATH"

echo "DEBUG: script start"

# Global DB connect timeout for psql (seconds)
export PGCONNECT_TIMEOUT=5

# ------------ Load env ------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/../.env}"

echo "DEBUG: before env load from ${ENV_FILE}"
if [ -f "${ENV_FILE}" ]; then
  echo "Loading environment from ${ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
else
  echo "WARN: ${ENV_FILE} not found, using defaults."
fi
echo "DEBUG: after env load"

# ------------ Config (with safe defaults) ------------
PG_PRIMARY_CONTAINER="${PG_PRIMARY_CONTAINER:-foodpulse-db}"
PG_REPLICA1_CONTAINER="${PG_REPLICA1_CONTAINER:-foodpulse-db-replica1}"
PG_REPLICA2_CONTAINER="${PG_REPLICA2_CONTAINER:-foodpulse-db-replica2}"
PG_REPLICA3_CONTAINER="${PG_REPLICA3_CONTAINER:-foodpulse-db-replica3}"
PG_HAPROXY_CONTAINER="${PG_HAPROXY_CONTAINER:-foodpulse-pg-haproxy}"

REDIS_MASTER_CONTAINER="${REDIS_MASTER_CONTAINER:-foodpulse-redis-master}"
REDIS_REPLICA1_CONTAINER="${REDIS_REPLICA1_CONTAINER:-foodpulse-redis-replica1}"
REDIS_REPLICA2_CONTAINER="${REDIS_REPLICA2_CONTAINER:-foodpulse-redis-replica2}"
REDIS_HAPROXY_CONTAINER="${REDIS_HAPROXY_CONTAINER:-foodpulse-redis-haproxy}"

FOODPULSE_UI_CONTAINER="${FOODPULSE_UI_CONTAINER:-foodpulse-ui}"
FOODPULSE_APP_CONTAINER="${FOODPULSE_APP_CONTAINER:-foodpulse-appserver}"

PG_USER="${FOODPULSE_DB_USER:-${YELB_DB_USER:-postgres}}"
PG_PASSWORD="${FOODPULSE_DB_PASSWORD:-${YELB_DB_PASSWORD:-admin}}"
PG_DB="${PG_DB:-${FOODPULSE_DB_NAME:-${YELB_DB_NAME:-foodpulse}}}"

REDIS_PASSWORD="${FOODPULSE_REDIS_PASSWORD:-${YELB_REDIS_PASSWORD:-admin}}"

STATUS=0   # 0 = OK, 1 = degraded

# Figure out the Docker network name attached to pg-haproxy
NETWORK_NAME="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "${PG_HAPROXY_CONTAINER}" 2>/dev/null || true)"

echo "=== CLUSTER STATUS (FOODPULSE HA) ==="
echo "Timestamp: $(date)"
echo "Docker network: ${NETWORK_NAME:-UNKNOWN}"
echo

# ---------- helpers ----------
pg_role_raw() {
  # prints "ip|t_or_f" or empty on failure
  local container="$1"
  docker exec -e PGPASSWORD="${PG_PASSWORD}" -e PGCONNECT_TIMEOUT=5 "${container}" \
    psql -U "${PG_USER}" -d "${PG_DB}" -tAc "SELECT inet_server_addr(), pg_is_in_recovery();" 2>/dev/null \
    | tr -d ' ' || true
}

pg_role_haproxy() {
  local port="$1"   # 5432 (RW) or 5433 (RO)
  [ -z "${NETWORK_NAME}" ] && return 0
  docker run --rm \
    --network "${NETWORK_NAME}" \
    -e PGPASSWORD="${PG_PASSWORD}" \
    -e PGCONNECT_TIMEOUT=5 \
    postgres:14 \
    psql -h pg-haproxy -p "${port}" -U "${PG_USER}" -d "${PG_DB}" -tAc \
      "SELECT inet_server_addr(), pg_is_in_recovery();" 2>/dev/null \
    | tr -d ' ' || true
}

redis_info_replication() {
  local container="$1"
  docker exec "${container}" \
    redis-cli -a "${REDIS_PASSWORD}" INFO replication 2>/dev/null \
    | egrep 'role:|master_host' || true
}

redis_info_replication_haproxy() {
  [ -z "${NETWORK_NAME}" ] && return 0
  docker run --rm \
    --network "${NETWORK_NAME}" \
    redis:7.2 \
    redis-cli -h redis-haproxy -p 6379 -a "${REDIS_PASSWORD}" \
      INFO replication 2>/dev/null \
    | egrep 'role:|master_host' || true
}

print_pg_role() {
  local label="$1"
  local raw="$2"
  if [ -z "${raw}" ]; then
    echo "    ${label}: [ERROR] no data"
    STATUS=1
    return
  fi
  local ip="${raw%%|*}"
  local flag="${raw##*|}"   # t or f
  local role
  if [ "${flag}" = "t" ]; then
    role="REPLICA"
  else
    role="PRIMARY"
  fi
  echo "    ${label}: ${ip} (${role})"
}

# ========================================================
# REDIS STATUS
# ========================================================
echo "==== STEP 1: REDIS START ===="
echo "[REDIS]"
echo "  Containers:"
echo "    Master candidate:  ${REDIS_MASTER_CONTAINER}"
echo "    Replica 1:         ${REDIS_REPLICA1_CONTAINER}"
echo "    Replica 2:         ${REDIS_REPLICA2_CONTAINER}"
echo

echo "  Direct view (from containers):"
m_out="$(redis_info_replication "${REDIS_MASTER_CONTAINER}")"
if [ -z "${m_out}" ]; then
  echo "    [ERROR] Could not query ${REDIS_MASTER_CONTAINER}"
  STATUS=1
else
  echo "    ${REDIS_MASTER_CONTAINER}:"
  echo "${m_out}" | sed 's/^/      /'
fi

r1_out="$(redis_info_replication "${REDIS_REPLICA1_CONTAINER}")"
if [ -z "${r1_out}" ]; then
  echo "    [ERROR] Could not query ${REDIS_REPLICA1_CONTAINER}"
  STATUS=1
else
  echo "    ${REDIS_REPLICA1_CONTAINER}:"
  echo "${r1_out}" | sed 's/^/      /'
fi

r2_out="$(redis_info_replication "${REDIS_REPLICA2_CONTAINER}")"
if [ -z "${r2_out}" ]; then
  echo "    [ERROR] Could not query ${REDIS_REPLICA2_CONTAINER}"
  STATUS=1
else
  echo "    ${REDIS_REPLICA2_CONTAINER}:"
  echo "${r2_out}" | sed 's/^/      /'
fi

echo
echo "  HAProxy view (redis-haproxy:6379):"
if [ -z "${NETWORK_NAME}" ]; then
  echo "    [WARN] No network detected; skipping HAProxy Redis view"
else
  hap_redis="$(redis_info_replication_haproxy)"
  if [ -z "${hap_redis}" ]; then
    echo "    [ERROR] Could not query via redis-haproxy"
    STATUS=1
  else
    echo "${hap_redis}" | sed 's/^/    /'
  fi
fi
echo "==== STEP 1: REDIS END ===="
echo

# ========================================================
# POSTGRES STATUS
# ========================================================
echo "==== STEP 2: POSTGRES START ===="
echo "[POSTGRES]"
echo "  Containers:"
echo "    Primary candidate: ${PG_PRIMARY_CONTAINER}"
echo "    Replica 1:         ${PG_REPLICA1_CONTAINER}"
echo "    Replica 2:         ${PG_REPLICA2_CONTAINER}"
echo "    Replica 3:         ${PG_REPLICA3_CONTAINER}"
echo

p_primary="$(pg_role_raw "${PG_PRIMARY_CONTAINER}")"
r1="$(pg_role_raw "${PG_REPLICA1_CONTAINER}")"
r2="$(pg_role_raw "${PG_REPLICA2_CONTAINER}")"
r3="$(pg_role_raw "${PG_REPLICA3_CONTAINER}")"

echo "  Direct view (from containers):"
print_pg_role "${PG_PRIMARY_CONTAINER}" "${p_primary}"
print_pg_role "${PG_REPLICA1_CONTAINER}" "${r1}"
print_pg_role "${PG_REPLICA2_CONTAINER}" "${r2}"
print_pg_role "${PG_REPLICA3_CONTAINER}" "${r3}"
echo

echo "  HAProxy view:"
if [ -z "${NETWORK_NAME}" ]; then
  echo "    [WARN] No Docker network detected for pg-haproxy; skipping RW/RO checks"
else
  rw_raw="$(pg_role_haproxy 5432)"
  ro_raw="$(pg_role_haproxy 5433)"

  echo "    RW pool (5432):"
  if [ -z "${rw_raw}" ]; then
    echo "      [ERROR] could not query via pg-haproxy RW (5432)"
    STATUS=1
  else
    print_pg_role "RW backend" "${rw_raw}"
  fi

  echo "    RO pool (5433):"
  if [ -z "${ro_raw}" ]; then
    echo "      [ERROR] could not query via pg-haproxy RO (5433)"
    STATUS=1
  else
    print_pg_role "RO backend" "${ro_raw}"
  fi
fi
echo "==== STEP 2: POSTGRES END ===="
echo
echo "DEBUG: finished POSTGRES block, entering APPLICATION checks..."
echo

# ========================================================
# APPLICATION HEALTH
# ========================================================
echo "==== STEP 3: APPLICATION START ===="
echo "[APPLICATION]"

if ! command -v curl >/dev/null 2>&1; then
  echo "  [ERROR] curl not found on host; cannot run HTTP checks."
  STATUS=1
else
  # foodpulse-ui via host (nginx on port 80)
  UI_URL="${UI_URL:-http://localhost:${FOODPULSE_UI_HOST_PORT:-8090}/}"
  UI_HTTP_CODE="$(
    curl --max-time 5 -s -o /dev/null -w "%{http_code}" "${UI_URL}" 2>/dev/null || echo "000"
  )"

  if [ "${UI_HTTP_CODE}" = "200" ]; then
    echo "  foodpulse-ui (${UI_URL}): OK (HTTP ${UI_HTTP_CODE})"
  else
    echo "  foodpulse-ui (${UI_URL}): ERROR (HTTP ${UI_HTTP_CODE})"
    STATUS=1
  fi

  # foodpulse-appserver via UI proxy: /api/getstats
  APP_STATS_URL="${APP_STATS_URL:-http://localhost:${FOODPULSE_UI_HOST_PORT:-8090}/api/getstats}"
  APP_HTTP_CODE="$(
    curl --max-time 5 -s -o /dev/null -w "%{http_code}" "${APP_STATS_URL}" 2>/dev/null || echo "000"
  )"

  if [ "${APP_HTTP_CODE}" = "200" ]; then
    echo "  foodpulse-appserver (via ${APP_STATS_URL}): OK (HTTP ${APP_HTTP_CODE})"
  else
    echo "  foodpulse-appserver (via ${APP_STATS_URL}): ERROR (HTTP ${APP_HTTP_CODE})"
    STATUS=1
  fi
fi
echo "==== STEP 3: APPLICATION END ===="
echo

# ========================================================
# SUMMARY
# ========================================================
echo "==== STEP 4: SUMMARY START ===="
echo "[SUMMARY]"
if [ "${STATUS}" -eq 0 ]; then
  echo "  Cluster status: OK"
else
  echo "  Cluster status: DEGRADED (see errors above)"
fi
echo "==== STEP 4: SUMMARY END ===="
echo "DEBUG: end-of-script before exit (STATUS=${STATUS})"

exit "${STATUS}"
