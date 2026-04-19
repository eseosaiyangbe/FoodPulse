# FoodPulse

## What This Repo Is

`FoodPulse` is a high-availability infrastructure lab built around the upstream `Yelb` application.

It is not just a simple app clone.
It is a workspace-owned wrapper around vendored upstream app code, with a local runtime contract that is intended to translate cleanly into Kubernetes later.

It is a local playground for:

- Redis replication and Sentinel failover
- Postgres primary/replica topology
- HAProxy routing for database and cache access

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

The repo is organized around a simple rule:

- `yelb/` contains the vendored upstream application source
- root-level folders like `haproxy/`, `scripts/`, `redis/`, and `postgres/` contain workspace-specific platform glue

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
./scripts/start.sh
```

The `yelb-appserver` service is intentionally built from the vendored local source in `yelb/yelb-appserver`.
That keeps the running appserver aligned with this repo's database contract instead of relying on an external image that may carry stale upstream assumptions.

Observability for this repo is handled by the central `Obervability-Stack`, not by a second monitoring stack inside `FoodPulse`.

After startup, useful checks include:

```bash
./scripts/cluster-status.sh
./scripts/redis-failover-drill.sh
./scripts/pg-failover-drill.sh
```

To stop the local stack:

```bash
./scripts/stop.sh
```

## Local URLs

- app: `http://localhost:8090`
- control plane app view: `http://localhost:4000/apps`

## Environment Contract

This repo expects a root `.env` file.

Start from:

- `.env.example`

Important variables include:

- `YELB_DB_SERVER`
- `YELB_DB_NAME`
- `YELB_REDIS_SERVER`
- `YELB_REDIS_PASSWORD`
- `YELB_DB_USER`
- `YELB_DB_PASSWORD`
- `PG_REPLICATOR_PASSWORD`
- `FOODPULSE_UI_HOST_PORT`
- `FOODPULSE_SENTINEL_HOST_PORT`
- `FOODPULSE_PG_RW_HOST_PORT`
- `FOODPULSE_PG_RO_HOST_PORT`
- `FOODPULSE_REDIS_HOST_PORT`

The default host-port contract is intentionally normalized so this repo can run beside the workspace control plane without colliding with shared ports or generic container names.

Today the upstream Redis and replication lab configs still expect:

- Redis password: `admin`
- replication password: `replicatorpass`

Those defaults are reflected in `.env.example` so the compose stack starts cleanly in this workspace.

## Cleanup Notes

Recent cleanup intentionally removed a few confusing duplicates:

- the canonical database bootstrap now comes from `yelb/yelb-db/init-yelb-db.sh`
- workspace-specific replication bootstrap now lives under `postgres/initdb/`
- the orphaned `ui/` scaffold was removed because it was not part of the running stack
- the old in-repo observability stack was removed so the central `Obervability-Stack` is the only monitoring layer in the workspace

## Known Caveats

- `command.sh` is a historical notes file, not the canonical startup path
- `scripts/pg-failover-drill.sh` is intentionally a manual lab drill, not a production failover controller
- this repo vendors the upstream `yelb/` app and wraps it in additional infrastructure
