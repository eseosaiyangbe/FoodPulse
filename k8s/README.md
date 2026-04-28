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

Structure:

- [base](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/base): shared application and stateful resources
- [overlays/dev](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/overlays/dev): local `k3s` deployment path
- [overlays/prod](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/overlays/prod): production-shaped overlay with larger topology and no git-stored local secrets
- [argocd](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/k8s/argocd): GitOps entrypoint

The authoritative operator walkthroughs are in:

- [k3s-dev-deployment.md](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/docs/k8s/k3s-dev-deployment.md)
- [architecture.md](/Users/raymond/Documents/DevOps-Easy-Learning/FoodPulse/docs/k8s/architecture.md)
