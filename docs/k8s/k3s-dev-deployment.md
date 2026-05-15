# FoodPulse k3s Dev Deployment

## Purpose

This is the owned local Kubernetes path for `FoodPulse`.

It exists to prove the application can move beyond the Compose lab while preserving the project’s portability across macOS and Linux.

## Prerequisites

- a working `k3s` context
- `kubectl`
- `docker`
- `helm`

The workspace helper will bootstrap the local runtime if needed:

```bash
../scripts/ensure-k3s-runtime.sh
```

## Deployment

From the `FoodPulse` repo root:

```bash
./scripts/k8s-start.sh
```

What the script does on a first deploy:

1. ensures the local `k3s` runtime is ready unless skipped
2. bootstraps the shared Vault and External Secrets platform unless skipped
3. installs `CloudNativePG` if it is missing
4. validates the `dev` overlay
5. builds the local `foodpulse-api:dev` and `foodpulse-ui:dev` images
6. applies the `FoodPulse/k8s/overlays/dev` overlay
7. waits for PostgreSQL, Redis, API, and UI readiness
8. runs the verification path

If `foodpulse-dev` already exists, `./scripts/k8s-start.sh` resumes the preserved namespace instead:

1. rehydrates the `CloudNativePG` PostgreSQL cluster
2. scales Redis back up
3. waits for PostgreSQL and Redis readiness
4. scales the API and UI back up
5. waits for the app deployments to become available

## Verification

Run:

```bash
./scripts/k8s-dev-verify.sh
```

The verification path checks:

- ingress reachability
- browser health endpoint
- API metrics exposure
- PostgreSQL readiness inside the cluster
- Redis and Sentinel responsiveness

## Lifecycle Controls

Run:

```bash
./scripts/k8s-stop.sh
```

This safely pauses FoodPulse by:

1. scaling the API and UI deployments to `0`
2. scaling the Redis StatefulSet to `0`
3. hibernating the `foodpulse-postgres` `CloudNativePG` cluster with `cnpg.io/hibernation=on`

This preserves:

- namespace `foodpulse-dev`
- PostgreSQL PVCs
- Redis PVCs
- application data

For a destructive reset, run:

```bash
./scripts/k8s-reset.sh --help
```

`k8s-reset.sh` deletes the entire `foodpulse-dev` namespace and all state inside it. Use it only when you intentionally want a full rebuild of the FoodPulse environment.

## Dev And Prod Split

The `dev` overlay is intentionally local-first:

- secrets are still local-environment oriented, but Vault is now the source of truth
- local images are used
- the namespace is `foodpulse-dev`

The `prod` overlay is intentionally stricter:

- no git-stored runtime secrets
- larger PostgreSQL and application topology
- intended for Vault-backed secret delivery and ArgoCD reconciliation
