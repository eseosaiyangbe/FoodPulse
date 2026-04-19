# FoodPulse

## What This Repo Is

`FoodPulse` is a high-availability infrastructure lab built around the upstream `Yelb` application.

It is not just a simple app clone.
It is a local playground for:

- Redis replication and Sentinel failover
- Postgres primary/replica topology
- HAProxy routing for database and cache access
- Prometheus, Grafana, Alertmanager, and blackbox monitoring

In the wider workspace, this repo plays the role of the **resilience and failover lab**.

## Main Runtime Shape

The stack includes:

- `yelb-ui`
- `yelb-appserver`
- Redis master plus replicas
- Redis Sentinel nodes
- Postgres primary plus replicas
- HAProxy for Postgres
- HAProxy for Redis
- Prometheus
- Grafana
- Alertmanager
- blackbox-exporter
- Postgres exporter
- Redis exporter

## Workspace Integration

This repo joins the shared Docker network:

```text
observability-net
```

The user-facing app is exposed to the control plane with the alias:

```text
foodpulse-ui
```

That alias matches the inventory in:

- `Obervability-Stack/ui-next/lib/monitored-apps.ts`

## Local Start

From the repo root:

```bash
cp .env.example .env
docker compose up -d
```

After startup, useful checks include:

```bash
./scripts/cluster-status.sh
./scripts/redis-failover-drill.sh
./scripts/pg-failover-drill.sh
```

## Local URLs

- app: `http://localhost:8090`
- Prometheus: `http://localhost:9095`
- Grafana: `http://localhost:3010`
- Alertmanager: `http://localhost:9096`
- HAProxy stats: `http://localhost:8410/stats`

## Environment Contract

This repo expects a root `.env` file.

Start from:

- `.env.example`

Important variables include:

- `YELB_DB_SERVER`
- `YELB_REDIS_SERVER`
- `YELB_REDIS_PASSWORD`
- `YELB_DB_USER`
- `YELB_DB_PASSWORD`
- `PG_REPLICATOR_PASSWORD`
- `POSTGRES_EXPORTER_DSN`
- `GF_ADMIN_USER`
- `GF_ADMIN_PASSWORD`
- `FOODPULSE_UI_HOST_PORT`
- `FOODPULSE_SENTINEL_HOST_PORT`
- `FOODPULSE_PG_RW_HOST_PORT`
- `FOODPULSE_PG_RO_HOST_PORT`
- `FOODPULSE_HAPROXY_STATS_HOST_PORT`
- `FOODPULSE_REDIS_HOST_PORT`
- `FOODPULSE_PROMETHEUS_HOST_PORT`
- `FOODPULSE_GRAFANA_HOST_PORT`
- `FOODPULSE_ALERTMANAGER_HOST_PORT`

The default host-port contract is intentionally normalized so this repo can run beside the workspace control plane without colliding with shared ports or generic container names.

Today the upstream Redis and replication lab configs still expect:

- Redis password: `admin`
- replication password: `replicatorpass`

Those defaults are reflected in `.env.example` so the compose stack starts cleanly in this workspace.

## Known Caveats

- `command.sh` is a historical notes file, not the canonical startup path
- `scripts/pg-failover-drill.sh` is intentionally a manual lab drill, not a production failover controller
- this repo vendors the upstream `yelb/` app and wraps it in additional infrastructure
