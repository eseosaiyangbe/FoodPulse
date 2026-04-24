#!/usr/bin/env bash

cat <<'EOF'
FoodPulse/command.sh is now a quick command index.

Canonical entry points:
- Start the stack: ./scripts/start.sh
- Stop the stack: ./scripts/stop.sh
- Check current topology: ./scripts/cluster-status.sh
- Check Docker storage and log growth: ./scripts/docker-storage-check.sh
- Run Redis failover drill: ./scripts/redis-failover-drill.sh
- Run Postgres failover drill: ./scripts/pg-failover-drill.sh

Modern app surfaces:
- UI: http://localhost:8090
- API health: http://localhost:8090/health
- API metrics: http://localhost:8090/metrics

This file stays on purpose as a small operator shortcut, not as a scratchpad.
EOF
