# FoodPulse Kubernetes Architecture

## Intent

`FoodPulse` keeps two different resilience stories on purpose:

- Docker Compose is the lab path, where `HAProxy` remains visible so failover mechanics are easy to teach and drill
- Kubernetes is the platform path, where the cluster should own routing and failover responsibilities more directly

That split preserves the local learning value without forcing a Docker-era routing pattern into the cluster.

## Runtime Model

The Kubernetes path is designed around four layers:

1. `Traefik` ingress for north-south HTTP traffic
2. `foodpulse-ui` and `foodpulse-api` as the application layer
3. `CloudNativePG` for PostgreSQL high availability and service discovery
4. Redis plus Sentinel-aware client discovery for cache failover

## What Changes From Compose

Compose keeps:

- `HAProxy` in front of PostgreSQL
- `HAProxy` in front of Redis
- manual failover drills for local learning

Kubernetes replaces:

- Postgres `HAProxy` with `CloudNativePG` `RW` service discovery
- Redis `HAProxy` with Sentinel-aware Redis client discovery

The application code keeps one contract:

- environment variables define the dependency endpoints
- the runtime decides whether those endpoints are Compose proxies or Kubernetes-native services

## PostgreSQL Direction

PostgreSQL uses `CloudNativePG` because it gives us a production-grade control plane for:

- primary/replica orchestration
- service-based application access
- failover
- storage-backed lifecycle management

The application should always use the generated or declared application credentials and the `RW` service. It should not pin itself to a pod.

## Redis Direction

Redis stays open-source and lightweight, but it stops depending on `HAProxy` in the cluster path.

Instead:

- Redis pods expose both Redis and Sentinel ports
- Sentinel monitors the Redis set and elects a new primary if needed
- the FoodPulse API uses Sentinel-aware discovery to find the current master

This is more Kubernetes-native than carrying a TCP proxy into the application topology, while still staying portable for local `k3s`.

## Environment Model

`dev`:

- optimized for local `k3s`
- Vault-backed secret materialization through External Secrets Operator
- local images
- smaller storage and replica expectations

`prod`:

- larger PostgreSQL topology
- larger Redis storage expectations
- multiple application replicas
- no git-stored environment secrets
- intended to receive secret material from the workspace Vault path

## GitOps And Secrets

This directory is compatible with the wider workspace direction:

- ArgoCD owns desired-state reconciliation
- Vault owns secret truth

That means:

- both `dev` and `prod` overlays now treat Vault as the secret source of truth
- External Secrets Operator materializes the Kubernetes Secret objects the workloads consume
