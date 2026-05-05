#!/bin/sh
set -eu

primary_fqdn="foodpulse-redis-0.foodpulse-redis-headless.${POD_NAMESPACE}.svc.cluster.local"

wait_for_primary() {
  local attempts=0

  while [ "${attempts}" -lt 60 ]; do
    if REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${primary_fqdn}" -p 6379 ping >/dev/null 2>&1; then
      return 0
    fi

    attempts=$((attempts + 1))
    sleep 2
  done

  echo "ERROR: Timed out waiting for Redis primary ${primary_fqdn}:6379" >&2
  exit 1
}

wait_for_primary

cat > /sentinel/sentinel.conf <<EOF
port 26379
bind 0.0.0.0
protected-mode no
dir /sentinel
logfile ""
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
sentinel monitor foodpulse-cache ${primary_fqdn} 6379 ${SENTINEL_QUORUM}
sentinel auth-pass foodpulse-cache ${REDIS_PASSWORD}
sentinel down-after-milliseconds foodpulse-cache 10000
sentinel failover-timeout foodpulse-cache 180000
sentinel parallel-syncs foodpulse-cache 1
EOF

exec redis-sentinel /sentinel/sentinel.conf
