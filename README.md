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
docker compose up -d
```

After startup, useful checks include:

```bash
./scripts/cluster-status.sh
./scripts/redis-failover-drill.sh
./scripts/pg-failover-drill.sh
```

## Local URLs

- app: `http://localhost`
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000`
- Alertmanager: `http://localhost:9093`
- HAProxy stats: `http://localhost:8404`

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

## Known Caveats

- `command.sh` is a historical notes file, not the canonical startup path
- `scripts/pg-failover-drill.sh` is intentionally a manual lab drill, not a production failover controller
- this repo vendors the upstream `yelb/` app and wraps it in additional infrastructure
