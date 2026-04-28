#!/bin/sh
set -eu

cat > /sentinel/sentinel.conf <<EOF
port 26379
bind 0.0.0.0
protected-mode no
dir /sentinel
logfile ""
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
sentinel monitor foodpulse-cache foodpulse-redis-0.foodpulse-redis-headless.${POD_NAMESPACE}.svc.cluster.local 6379 ${SENTINEL_QUORUM}
sentinel auth-pass foodpulse-cache ${REDIS_PASSWORD}
sentinel down-after-milliseconds foodpulse-cache 10000
sentinel failover-timeout foodpulse-cache 180000
sentinel parallel-syncs foodpulse-cache 1
EOF

exec redis-sentinel /sentinel/sentinel.conf
