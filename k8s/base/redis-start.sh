#!/bin/sh
set -eu

ordinal="${HOSTNAME##*-}"
node_fqdn="${HOSTNAME}.foodpulse-redis-headless.${POD_NAMESPACE}.svc.cluster.local"
primary_fqdn="foodpulse-redis-0.foodpulse-redis-headless.${POD_NAMESPACE}.svc.cluster.local"

mkdir -p /data

if [ ! -f /data/redis.conf ]; then
  cat > /data/redis.conf <<EOF
port 6379
bind 0.0.0.0
protected-mode no
appendonly yes
dir /data
dbfilename dump.rdb
appendfilename appendonly.aof
requirepass ${REDIS_PASSWORD}
masterauth ${REDIS_PASSWORD}
replica-announce-ip ${node_fqdn}
replica-announce-port 6379
logfile ""
EOF

  if [ "${ordinal}" != "0" ]; then
    cat >> /data/redis.conf <<EOF
replicaof ${primary_fqdn} 6379
EOF
  fi
fi

exec redis-server /data/redis.conf
