# FoodPulse Cloud CI/CD

This repository separates image publishing, active dev verification, and held production promotion.

## Delivery Lanes

- `validate.yml`
  Runs repository validation only.
- `publish-dockerhub-images.yml`
  Builds and publishes `foodpulse-api` and `foodpulse-ui` to Docker Hub.
- `smoke-dev-public.yml`
  Verifies the active public `dev` edge.
- `promote-prod.yml`
  Updates the held production Kustomize overlay to a reviewed immutable image tag through a pull request.

## Docker Hub Variables

Set these repository variables and secrets before enabling the image workflow:

- `vars.DOCKERHUB_USERNAME`
- `vars.DOCKERHUB_API_REPOSITORY`
  Optional. Defaults to `foodpulse-api`.
- `vars.DOCKERHUB_UI_REPOSITORY`
  Optional. Defaults to `foodpulse-ui`.
- `secrets.DOCKERHUB_TOKEN`

## Image Policy

- branch pushes publish branch tags and immutable `git-<sha>` tags
- the `main` branch also publishes the mutable `dev` alias
- version tags publish immutable `git-<sha>` tags plus mutable `prod` and `latest` aliases
- the current runtime truth is the `dev` path, not the held `prod` path
- production should promote immutable `git-<sha>` tags through GitOps when that path is intentionally activated

## Promotion Boundary

`promote-prod.yml` does not mutate the cluster.

It:

- validates the requested immutable tag format
- verifies the API and UI images exist in Docker Hub
- updates `k8s/overlays/prod/kustomization.yaml`
- opens a pull request for review and merge

Argo CD remains the deployment authority after that merge.

## Current Operating Posture

- `dev` is the active environment and should be verified continuously
- `prod` remains a stronger Git contract, not the active runtime path
- manual production promotion is preserved so the repo does not lose its future-ready control boundary
