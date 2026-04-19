#!/bin/bash
set -e

# Default PGDATA for official postgres image
: "${PGDATA:=/var/lib/postgresql/data}"

PRIMARY_HOST="yelb-db"
REPL_USER="replicator"

echo "Replica starting with PGDATA=${PGDATA}"

# Only initialize if PGDATA is empty (no PG_VERSION yet)
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "PGDATA is empty, initializing replica from primary ${PRIMARY_HOST}..."

  # Loop until pg_basebackup succeeds
  until pg_basebackup \
      -h "${PRIMARY_HOST}" \
      -D "${PGDATA}" \
      -U "${REPL_USER}" \
      -Fp -Xs -P -R; do
    echo "pg_basebackup failed, retrying in 5 seconds..."
    sleep 5
  done

  echo "Base backup completed successfully."
fi

echo "Starting postgres in replica mode..."
exec docker-entrypoint.sh postgres
