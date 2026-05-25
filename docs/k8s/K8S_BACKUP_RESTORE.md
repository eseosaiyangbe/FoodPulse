# FoodPulse Kubernetes Backup And Restore

This document defines the owned backup and restore contract for the `foodpulse-dev` Kubernetes slice.

## Scope

The current FoodPulse Kubernetes backup and restore contract covers:

- PostgreSQL business data
  - `venues`
  - `vote_events`
- Redis continuity state
  - primary Redis dataset used by the application

The contract does not currently treat every Redis-related surface the same way.

What is protected:

- Redis primary continuity state on the PVC for `foodpulse-redis-0`

What is not independently protected:

- Sentinel runtime metadata under `/sentinel`
- replica-local Redis PVC state as a separate authoritative source

Why that boundary is explicit:

- Sentinel state is regenerated from configuration at startup
- replica Redis pods are designed to follow the primary and converge back to the intended topology
- the authoritative recovery contract for this phase is PostgreSQL plus Redis primary continuity state

## Storage Model

Backups are stored on:

- PVC: `foodpulse-backup-storage`

Scheduled state backups are produced by:

- CronJob: `foodpulse-state-backup`

Default scheduled behavior:

- daily backup run at `0 4 * * *` in `Etc/UTC`
- keep the most recent `7` backup sets

Timezone policy:

- the backup CronJob is pinned to `Etc/UTC`
- backup filenames are written in UTC
- operator-facing local time conversions should be treated as secondary documentation only

Each backup run produces:

- `foodpulse-postgres-<timestamp>.dump`
- `foodpulse-redis-<timestamp>.rdb`

Retention policy:

- PostgreSQL dumps keep the newest `7` artifacts
- Redis snapshots keep the newest `7` artifacts
- retention is count-based, not file-age-based

## Operator Commands

Run from the `FoodPulse` repo root.

Create a one-off backup:

```bash
./scripts/k8s-backup-run.sh
```

Inspect stored backups:

```bash
./scripts/k8s-backup-inspect.sh
```

Delete all stored backups:

```bash
./scripts/k8s-backup-delete.sh --all
```

Delete older backups but keep the newest PostgreSQL dump and newest Redis snapshot:

```bash
./scripts/k8s-backup-delete.sh --keep-latest
```

Restore the latest backup set:

```bash
./scripts/k8s-restore-run.sh
```

Restore a specific backup set:

```bash
./scripts/k8s-restore-run.sh foodpulse-postgres-YYYYMMDDTHHMMSSZ.dump foodpulse-redis-YYYYMMDDTHHMMSSZ.rdb
```

Verify restore state:

```bash
./scripts/k8s-restore-verify.sh
```

## GitOps Control During Restore Drills

Because `foodpulse-dev` is ArgoCD-managed, a live restore drill must temporarily suspend automated sync before scaling workloads down.

Suspend automation:

```bash
kubectl patch application internal-developer-platform-dev-root -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl patch application foodpulse-dev -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl get application internal-developer-platform-dev-root foodpulse-dev -n argocd -o wide
```

Re-enable automation after the drill:

```bash
kubectl patch application internal-developer-platform-dev-root -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl patch application foodpulse-dev -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}'
kubectl annotate application foodpulse-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application internal-developer-platform-dev-root foodpulse-dev -n argocd -o wide
```

## Restore Behavior

The restore path is intentionally sequenced.

Before restore:

- scale `foodpulse-api` to `0`
- scale `foodpulse-ui` to `0`
- scale the `foodpulse-redis` StatefulSet to `0`

During restore:

- restore PostgreSQL data from the selected `.dump` through the current CloudNativePG primary pod's local `postgres` superuser path
- restore Redis primary continuity state from the selected `.rdb`

After restore:

- scale the Redis StatefulSet back to its prior replica count
- scale the FoodPulse application deployments back to their prior replica counts
- wait for those workloads to become ready again

This sequencing is deliberate.

FoodPulse restore must not compete with active writers while PostgreSQL and Redis primary state are being restored.

The PostgreSQL restore path is intentionally stronger than the application role.

Why:

- the live `venues` and `vote_events` tables are owned by `postgres`
- restoring with the weaker `foodpulse` application role fails on `--clean` object teardown
- the restore helper therefore streams the dump through the current CNPG primary pod and executes `pg_restore` there as local `postgres`

## Verification Standard

A restore is not complete because the restore pod succeeded.

A restore is complete only when:

- PostgreSQL content is queryable again
- representative business tables exist
- representative row counts are queryable again
- Redis primary PVC state is present again
- `foodpulse-api`, `foodpulse-ui`, and `foodpulse-redis` are ready again

Use:

```bash
./scripts/k8s-restore-verify.sh
```

## Useful Live Commands

Check ArgoCD state for the app:

```bash
kubectl get application foodpulse-dev -n argocd -o wide
```

Check backup resources directly:

```bash
kubectl get cronjob,pvc -n foodpulse-dev | grep -E 'foodpulse-state-backup|foodpulse-backup-storage|NAME'
```

Check live runtime state:

```bash
kubectl get pods,pvc -n foodpulse-dev
```

Inspect recent namespace events:

```bash
kubectl get events -n foodpulse-dev --sort-by=.lastTimestamp | tail -n 30
```

## Pre-Restore Sanity Checks

Before you run a restore, do these checks:

1. confirm the app is currently `Synced` and `Healthy`

```bash
kubectl get application foodpulse-dev -n argocd -o wide
```

2. confirm the backup files you plan to use exist and are non-zero

```bash
./scripts/k8s-backup-inspect.sh
```

3. confirm the FoodPulse workloads are currently stable enough to scale down safely

```bash
kubectl get pods -n foodpulse-dev
```

4. if you are targeting a named backup set, record the exact filenames first

```bash
./scripts/k8s-restore-run.sh foodpulse-postgres-YYYYMMDDTHHMMSSZ.dump foodpulse-redis-YYYYMMDDTHHMMSSZ.rdb
```

5. suspend ArgoCD automated sync for the drill window

```bash
kubectl patch application internal-developer-platform-dev-root -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl patch application foodpulse-dev -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
```

## End-To-End Backup Flow

```bash
cd /Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse
./scripts/k8s-backup-run.sh
./scripts/k8s-backup-inspect.sh
kubectl get cronjob,pvc -n foodpulse-dev | grep -E 'foodpulse-state-backup|foodpulse-backup-storage|NAME'
kubectl get application foodpulse-dev -n argocd -o wide
```

## End-To-End Restore Flow

```bash
cd /Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse
kubectl get application foodpulse-dev -n argocd -o wide
kubectl get application internal-developer-platform-dev-root foodpulse-dev -n argocd -o wide
kubectl get pods -n foodpulse-dev
./scripts/k8s-backup-inspect.sh
kubectl patch application internal-developer-platform-dev-root -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
kubectl patch application foodpulse-dev -n argocd --type json -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'
./scripts/k8s-restore-run.sh foodpulse-postgres-YYYYMMDDTHHMMSSZ.dump foodpulse-redis-YYYYMMDDTHHMMSSZ.rdb
./scripts/k8s-restore-verify.sh
kubectl patch application internal-developer-platform-dev-root -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl patch application foodpulse-dev -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}'
kubectl annotate application foodpulse-dev -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get application internal-developer-platform-dev-root foodpulse-dev -n argocd -o wide
kubectl get application foodpulse-dev -n argocd -o wide
kubectl get pods -n foodpulse-dev
kubectl get events -n foodpulse-dev --sort-by=.lastTimestamp | tail -n 30
```

## Live Validation Notes

The FoodPulse Phase 8 backup and restore path was validated live on `2026-05-25`.

Validated backup set:

- `foodpulse-postgres-20260525T033228Z.dump`
- `foodpulse-redis-20260525T033228Z.rdb`

Validated restore result:

- PostgreSQL tables restored:
  - `venues`
  - `vote_events`
- PostgreSQL row counts after restore:
  - `venues=8`
  - `vote_events=5`
- Redis primary PVC state restored:
  - `/redis-primary/dump.rdb`
  - `/redis-primary/appendonlydir/appendonly.aof.1.base.rdb`
  - `/redis-primary/appendonlydir/appendonly.aof.1.incr.aof`
  - `/redis-primary/appendonlydir/appendonly.aof.manifest`
  - `/redis-primary/redis.conf`

## Issues Encountered And Fixes Applied

### 1. PostgreSQL backup client version mismatch

Initial manual backups failed because the backup container was using `postgres:16-alpine` against a PostgreSQL 18 server.

Observed failure:

```text
pg_dump: error: aborting because of server version mismatch
server version: 18.3 ...
pg_dump version: 16.13
```

Fix:

- updated the FoodPulse PostgreSQL backup and restore helper image to `postgres:18-alpine`

### 2. PostgreSQL restore ownership failure with the application role

Initial restore attempts failed because `pg_restore --clean` was running as the `foodpulse` application user while live tables were owned by `postgres`.

Observed failure:

```text
pg_restore: error: could not execute query: ERROR: must be owner of table vote_events
```

Fix:

- changed the restore path to stream the dump through the current CNPG primary pod
- execute `pg_restore` there as local `postgres`

### 3. Redis quiesce in the local restore drill

During the restore drill, Redis scale-down occasionally stalled in the single-node local runtime and required force deletion of terminating pods before the restore helper could mount the primary PVC.

Operational recovery:

```bash
kubectl delete pod foodpulse-redis-1 -n foodpulse-dev --grace-period=0 --force
kubectl delete pod foodpulse-redis-0 -n foodpulse-dev --grace-period=0 --force
```

This is documented as a local-runtime restore nuance, not as the preferred steady-state behavior.

## Phase 8 Position

This is the next concrete implementation of the Phase 8 backup and restore standard in the workspace.

Implementation order now stands at:

1. `OpenSIS` reference pattern
2. `observability-stack` control-plane contract
3. `SwiftPay`
4. `FoodPulse`
5. `MemFlip`

## Image Rebuild Note

No custom image rebuild is required for this backup and restore slice.

This implementation uses:

- Kubernetes manifests
- repo-local operator scripts
- stock `postgres:18-alpine`, `redis:7.2-alpine`, and `busybox:1.36` runtime images
