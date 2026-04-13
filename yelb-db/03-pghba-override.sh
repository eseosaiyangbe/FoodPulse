#!/bin/bash
set -e

# PGDATA is set by the official postgres entrypoint
: "${PGDATA:=/var/lib/postgresql/data}"

echo "Adding replication rule for 'replicator' to pg_hba.conf ..."
echo "host replication replicator 0.0.0.0/0 trust" >> "$PGDATA/pg_hba.conf"
