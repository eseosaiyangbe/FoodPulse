#!/usr/bin/env bash

cat <<'EOF'
FoodPulse/command.sh is kept only as a historical notes file.

Canonical entry points:
- Start the stack: docker compose up -d
- Check current topology: ./scripts/cluster-status.sh
- Run Redis failover drill: ./scripts/redis-failover-drill.sh
- Run Postgres failover drill: ./scripts/pg-failover-drill.sh

Why this file still exists:
- earlier work in this repo used it as a scratchpad for operator notes
- removing it entirely would erase context that is still useful during cleanup
- executing it should now be safe and predictable instead of failing on free-form text

Archived notes from the original scratchpad are preserved below as comments.
EOF

# Historical notes
#
# clean architectural design
# made redis-server the msater
# kept odilia-redi01 as the slaveof/replica of redis-server
#
# Sentinel container crashing
# problem:
# was read only
# - ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf:ro
#
# Solution:
# made it writeable
# - ./redis/replica/redis.conf:/usr/local/etc/redis/redis.conf
#
# Commands to verify roles
#
# Check master (redis-server)
# docker exec -it redis-server redis-cli INFO replication
#
# Look for:
# role:master
# connected_slaves:1
# A line like:
# slave0:ip=odilia-redis01 (or your ip addr),port=6379,state=online,...
#
# Check replica (odilia-redis01)
# docker exec -it odilia-redis01 redis-cli INFO replication
#
# Look for:
# role:slave
# master_host:redis-server
# master_link_status:up
#
# Check sentinel view of the master
# docker exec -it odilia-redis-sentinel01 redis-cli -p 26379 SENTINEL masters
#
# You should see a block for mymaster with:
# name -> mymaster
# ip -> redis-server
# port -> 6379
# flags -> master
#
# Compose file without DB replication:
# (retained in git history and in earlier working notes; omitted here for brevity)
#
# update
# redis:4.0.2 was used for the original project
# it does not allow replicaof, i had to use slaveof.
