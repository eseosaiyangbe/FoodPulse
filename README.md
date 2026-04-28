# FoodPulse

## What This Repo Is

`FoodPulse` is now a workspace-owned application and resiliency lab.

We replaced the inherited legacy runtime with an owned stack:

- a modern React UI in [ui](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/ui)
- a Node/Express API in [api](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/api)
- a Postgres primary/replica topology
- Redis replication plus Sentinel failover
- HAProxy routing for Postgres and Redis
- an owned Kubernetes path in [k8s](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s)

In the wider workspace, `FoodPulse` is still the **resilience and failover lab**, but it now has an app surface we control end to end.

## Main Runtime Shape

The stack includes:

- `foodpulse-ui`
- `foodpulse-api`
- Redis master plus replicas
- Redis Sentinel nodes
- Postgres primary plus replicas
- HAProxy for Postgres
- HAProxy for Redis

The repo layout is intentionally simple:

- [ui](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/ui) contains the modern frontend
- [api](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/api) contains the modern backend
- [postgres](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/postgres), [redis](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/redis), [sentinel](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/sentinel), and [haproxy](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/haproxy) contain the HA lab infrastructure
- [k8s](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s) contains the owned Kubernetes deployment model for `dev` and `prod`
- [scripts](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/scripts) contains operator workflows

## Workspace Integration

This repo joins the shared Docker network:

```text
observability-net
```

The user-facing app is exposed to the control plane with the alias:

```text
foodpulse-ui
```

That alias matches the inventory in the central observability stack.

Observability for this repo is handled by the central `Obervability-Stack`, not by a second monitoring stack inside `FoodPulse`.

## Local Start

From the repo root:

```bash
cp .env.example .env
./scripts/start.sh
```

If you are upgrading from an older local FoodPulse stack, run `docker compose down -v` once before the first modernized startup so the new app role and schema bootstrap can recreate cleanly.

Useful follow-up commands:

```bash
./scripts/cluster-status.sh
./scripts/docker-storage-check.sh
./scripts/redis-failover-drill.sh
./scripts/pg-failover-drill.sh
```

To stop the local stack:

```bash
./scripts/stop.sh
```

## Kubernetes Path

`FoodPulse` now has an owned Kubernetes path that intentionally diverges from the Compose lab where the platform should do better:

- Compose keeps `HAProxy` because it is useful for local failover drills
- Kubernetes replaces Postgres `HAProxy` with `CloudNativePG`
- Kubernetes replaces Redis `HAProxy` with Sentinel-aware client discovery
- `dev` and `prod` are separate overlays from the start, not an afterthought

The active local cluster path is `k3s`:

```bash
./scripts/k8s-dev-deploy.sh
./scripts/k8s-dev-verify.sh
./scripts/k8s-dev-destroy.sh
```

Authoritative Kubernetes references:

- [k8s](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s)
- [k3s-dev-deployment.md](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/docs/k8s/k3s-dev-deployment.md)
- [architecture.md](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/docs/k8s/architecture.md)

## Local URLs

- app: `http://localhost:8090`
- API direct host port: `http://localhost:3102`
- app health via UI proxy: `http://localhost:8090/health`
- app metrics via UI proxy: `http://localhost:8090/metrics`
- control plane app view: `http://localhost:4000/apps`

## Environment Contract

This repo expects a root `.env` file.

Start from:

- [.env.example](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/.env.example)

Important variables include:

- `FOODPULSE_DB_SERVER`
- `FOODPULSE_DB_PORT`
- `FOODPULSE_DB_NAME`
- `FOODPULSE_DB_USER`
- `FOODPULSE_DB_PASSWORD`
- `FOODPULSE_REDIS_SERVER`
- `FOODPULSE_REDIS_PORT`
- `FOODPULSE_REDIS_PASSWORD`
- `FOODPULSE_REDIS_SENTINELS`
- `FOODPULSE_REDIS_MASTER_NAME`
- `FOODPULSE_REDIS_SENTINEL_PASSWORD`
- `FOODPULSE_ALLOWED_ORIGIN`
- `PG_REPLICATOR_PASSWORD`
- `FOODPULSE_UI_HOST_PORT`
- `FOODPULSE_API_HOST_PORT`
- `FOODPULSE_SENTINEL_HOST_PORT`
- `FOODPULSE_PG_RW_HOST_PORT`
- `FOODPULSE_PG_RO_HOST_PORT`
- `FOODPULSE_REDIS_HOST_PORT`

The default host-port contract is intentionally normalized so this repo can run beside the workspace control plane without colliding with shared ports or generic container names.

## Kubernetes Readiness

The owned app surface is now structured to translate cleanly into Kubernetes:

- separate UI and API images
- environment-driven runtime contracts
- dedicated health endpoint
- dedicated metrics endpoint
- `CloudNativePG` for PostgreSQL failover and service discovery
- Sentinel-aware Redis failover without an application-owned proxy
- explicit `dev` and `prod` overlays

## Known Caveats

- `scripts/pg-failover-drill.sh` is intentionally a manual lab drill, not a production failover controller
- the Compose Postgres and Redis HA topologies are educational and operator-friendly, not full self-healing platforms
- the Kubernetes `prod` overlay is a deployment contract, not a fully exercised production environment yet
- the central control plane currently blackbox-checks the browser surface; it does not yet scrape the new API metrics endpoint directly

## Operator Notes

Run `./scripts/docker-storage-check.sh` during incident triage or before demos if the local Docker runtime has been carrying multiple projects for a while. It reports:

- overall Docker storage usage
- each FoodPulse container's logging policy
- the largest Docker `json-file` logs it can inspect from the local runtime

The current `FoodPulse` Compose file does not pin `platform:` to `linux/amd64`. If Apple Silicon hosts still show AMD64 warnings for Redis or HAProxy, that comes from the local Docker image/runtime state rather than the repo configuration. In that case, inspect the local image platform selection and refresh the affected images if needed.
