# FoodPulse Kubernetes

This directory is the owned Kubernetes path for `FoodPulse`.

It is intentionally separate from the Docker Compose lab:

- Docker Compose keeps `HAProxy` because it is the local resilience teaching path
- Kubernetes replaces that dependency routing with cluster-native components

Current direction:

- `Traefik` for ingress
- `CloudNativePG` for PostgreSQL
- Redis plus Sentinel-aware client discovery without `HAProxy`
- `dev` overlay for local `k3s`
- `prod` overlay as the production contract
- Vault as the secret source of truth for both environments

Structure:

- [base](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/base): shared application and stateful resources
- [overlays/dev](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/overlays/dev): local `k3s` deployment path
- [overlays/prod](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/overlays/prod): production-shaped overlay with larger topology and no git-stored local secrets
- [argocd](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/argocd): GitOps entrypoint

The authoritative operator walkthroughs are in:

- [k3s-dev-deployment.md](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/docs/k8s/k3s-dev-deployment.md)
- [architecture.md](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/docs/k8s/architecture.md)

## Backup And Restore

The owned Kubernetes path now has an explicit backup and restore path.

Coverage:

- PostgreSQL-backed FoodPulse business data
- Redis primary continuity state

Primary reference:

- [K8S_BACKUP_RESTORE.md](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/docs/k8s/K8S_BACKUP_RESTORE.md)

Fast operator checks:

```bash
kubectl get application foodpulse-dev -n argocd -o wide
kubectl get cronjob,pvc -n foodpulse-dev | grep -E 'foodpulse-state-backup|foodpulse-backup-storage|NAME'
./scripts/k8s-backup-run.sh
./scripts/k8s-backup-inspect.sh
./scripts/k8s-backup-delete.sh --keep-latest
./scripts/k8s-restore-run.sh foodpulse-postgres-YYYYMMDDTHHMMSSZ.dump foodpulse-redis-YYYYMMDDTHHMMSSZ.rdb
./scripts/k8s-restore-verify.sh
```
