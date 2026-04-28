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
./scripts/k8s-dev-deploy.sh
```

What the script does:

1. ensures the local `k3s` runtime is ready unless skipped
2. bootstraps the shared Vault and External Secrets platform unless skipped
3. installs `CloudNativePG` if it is missing
4. validates the `dev` overlay
5. builds the local `foodpulse-api:dev` and `foodpulse-ui:dev` images
6. applies the `FoodPulse/k8s/overlays/dev` overlay
7. waits for PostgreSQL, Redis, API, and UI readiness
8. runs the verification path

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

## Destroy

Run:

```bash
./scripts/k8s-dev-destroy.sh
```

This removes the `dev` overlay resources from the cluster. It does not remove the shared `CloudNativePG` operator.

## Dev And Prod Split

The `dev` overlay is intentionally local-first:

- secrets are still local-environment oriented, but Vault is now the source of truth
- local images are used
- the namespace is `foodpulse-dev`

The `prod` overlay is intentionally stricter:

- no git-stored runtime secrets
- larger PostgreSQL and application topology
- intended for Vault-backed secret delivery and ArgoCD reconciliation
