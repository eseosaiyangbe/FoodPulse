# FoodPulse scripts

## k3s dev operator path

This is the current owned local Kubernetes path for FoodPulse.

```bash
./scripts/k8s-start.sh
./scripts/k8s-stop.sh
./scripts/k8s-reset.sh --help
./scripts/smoke-dev.sh
./scripts/k8s-dev-verify.sh
./scripts/k8s-backup-run.sh
./scripts/k8s-backup-inspect.sh
./scripts/k8s-backup-delete.sh --help
./scripts/k8s-restore-run.sh
./scripts/k8s-restore-verify.sh
```

Use this when you want FoodPulse running on the shared local `k3s` runtime with Traefik and the shared control plane.

For ArgoCD-managed lifecycle drills, suspend automation before a preserved stop and re-enable it after resume:

```bash
./scripts/k8s-stop.sh --wait --suspend-gitops
./scripts/k8s-start.sh --resume-gitops
```

For preserved namespace resume after `./scripts/k8s-stop.sh`, `./scripts/k8s-start.sh` now gives Redis a longer rollout window by default. You can extend it further when needed:

```bash
REDIS_ROLLOUT_TIMEOUT=900s ./scripts/k8s-start.sh
```

See [FoodPulse k3s dev deployment](../docs/k8s/k3s-dev-deployment.md).

See [Kubernetes backup and restore](../docs/k8s/K8S_BACKUP_RESTORE.md).

### `smoke-dev.sh`
**Public dev smoke helper** for the active `FoodPulse` runtime path.

```bash
./scripts/smoke-dev.sh
```

Features:

- confirms the `foodpulse-dev` Argo CD application is present
- checks current workload state in `foodpulse-dev`
- verifies the public dev root and `/health` endpoints

### `k8s-backup-run.sh`
**FoodPulse state backup runner** for the owned `k3s` path.

```bash
./scripts/k8s-backup-run.sh
```

Features:

- creates a one-off backup job from the scheduled FoodPulse state backup CronJob
- waits for any previous manual backup job deletion to finish before creating a retry
- streams PostgreSQL and Redis backup container logs

### `k8s-backup-inspect.sh`
**Backup artifact inspector** for the FoodPulse backup PVC.

```bash
./scripts/k8s-backup-inspect.sh
```

Features:

- mounts `foodpulse-backup-storage`
- lists retained PostgreSQL dump and Redis snapshot artifacts

### `k8s-backup-delete.sh`
**Backup artifact cleanup helper** for the FoodPulse backup PVC.

```bash
./scripts/k8s-backup-delete.sh --all
./scripts/k8s-backup-delete.sh --keep-latest
```

Features:

- deletes all backup artifacts when requested
- prunes older backup artifacts while keeping the newest backup set
- removes stale zero-byte PostgreSQL `.dump.tmp` files left behind by failed backup attempts
- mounts `foodpulse-backup-storage` directly so cleanup is reliable on local `k3s`

### `k8s-restore-run.sh`
**FoodPulse state restore runner** for the owned `k3s` path.

```bash
./scripts/k8s-restore-run.sh
./scripts/k8s-restore-run.sh foodpulse-postgres-YYYYMMDDTHHMMSSZ.dump foodpulse-redis-YYYYMMDDTHHMMSSZ.rdb
```

Features:

- scales the FoodPulse application deployments and Redis StatefulSet down before restore
- restores PostgreSQL-backed business data through the current CNPG primary pod's local `postgres` superuser path
- restores Redis primary continuity state
- scales workloads back up after restore
- expects that Redis quiesce may occasionally require forced pod deletion in the local single-node drill window

Before using this against a live ArgoCD-managed `foodpulse-dev` namespace, suspend automated sync on both:

- `internal-developer-platform-dev-root`
- `foodpulse-dev`

### `k8s-restore-verify.sh`
**Restore verification runner** for the owned `k3s` path.

```bash
./scripts/k8s-restore-verify.sh
```

Features:

- confirms the main FoodPulse workloads are ready again
- waits for PostgreSQL to accept connections before running SQL validation
- verifies PostgreSQL business tables exist and are queryable
- verifies Redis primary PVC state files exist on the restored volume
