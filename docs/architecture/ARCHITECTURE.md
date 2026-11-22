# FoodPulse Platform Architecture

![FoodPulse platform architecture](foodpulse-platform-architecture.png)

This document is the architecture design of record for the FoodPulse Resilience Lab. The image above is rendered from the Mermaid source in this file, so the picture and the source never drift apart.

## The design in one paragraph

FoodPulse treats high availability as something to prove, not to draw. The owned application (React UI, Node and Express API) sits in front of two data tiers: PostgreSQL primary plus replicas, and Redis master plus replicas watched by Sentinel. In the Compose lab, HAProxy fronts both tiers because an operator can inspect backend state directly during a drill, which makes cause and effect legible. On the Kubernetes path that proxy tier is deliberately removed: CloudNativePG manages PostgreSQL, Sentinel aware client discovery handles Redis, Vault is the secret source of truth for dev and prod through External Secrets Operator, and dev and prod are separate overlays from the start, with dev the active runtime truth and prod a held contract. Observability is central, not duplicated: FoodPulse joins the shared observability network and appears in the Obervability-Stack control plane under the foodpulse-ui alias. Delivery runs four lanes: validate; publish Docker Hub images with immutable git-sha tags, Trivy reporting, SPDX SBOM generation, and Cosign signing; smoke verification of the public dev edge; and manual prod promotion through a pull request. Validation is the drill model: trigger a bounded failure, observe proxy, application, and dependency together, run the failover procedure, validate application impact and recovery, and record the drill against telemetry (live audit 23 of 23 checks, Phase 6 lab audit).

## Architecture diagram, Mermaid source

```mermaid
flowchart TB
    User["User"]
    Operator["Operator"]

    subgraph Edge["Edge and ingress"]
        CF["Cloudflare Tunnel<br/>foodpulse.eseosadevbox.com"]
        Traefik["Traefik ingress<br/>Kubernetes path"]
    end

    subgraph Lab["Compose lab, built for drills"]
        HAProxyPG_L["HAProxy for PostgreSQL<br/>Visible backend state"]
        HAProxyRedis_L["HAProxy for Redis<br/>Visible backend state"]
    end

    subgraph Cluster["FoodPulse workload"]
        subgraph App["Application, owned end to end"]
            UI["foodpulse-ui<br/>React frontend"]
            API["foodpulse-api<br/>Node and Express"]
        end

        subgraph DataPG["PostgreSQL tier"]
            PGPrimary["Primary"]
            PGReplica["Replicas"]
            CNPG["CloudNativePG<br/>Kubernetes path<br/>replaces HAProxy"]
            PGPrimary -->|"replication"| PGReplica
        end

        subgraph DataRedis["Redis tier"]
            RedisMaster["Master"]
            RedisReplica["Replicas"]
            Sentinel["Redis Sentinel<br/>Failover decisions<br/>and client discovery"]
            RedisMaster -->|"replication"| RedisReplica
            Sentinel -->|"monitors and promotes"| RedisMaster
        end
    end

    subgraph PlatformObs["Observability, central, not duplicated"]
        ControlPlane["Obervability-Stack control plane<br/>foodpulse-ui alias in inventory"]
        Prom["Prometheus, Grafana, Loki<br/>Metrics, dashboards, logs"]
        ControlPlane --- Prom
    end

    subgraph PlatformSecrets["Platform secrets, Kubernetes path"]
        Vault["HashiCorp Vault<br/>Source of truth, dev and prod"]
        ESO["External Secrets Operator<br/>Materializes runtime secrets"]
        Vault --> ESO
        ESO --> Cluster
    end

    subgraph Delivery["Delivery, four lanes"]
        Git["Git repository<br/>Dev and prod overlays"]
        CI["Validate, publish Docker Hub<br/>Immutable git-sha tags, Trivy,<br/>SPDX SBOM, Cosign signing"]
        Smoke["Smoke dev public<br/>Verifies the live dev edge"]
        Promote["Promote prod<br/>Manual, through a<br/>pull request"]
        Git --> CI
        CI --> Cluster
        Smoke --> CF
        Promote --> Git
    end

    subgraph Drills["The drill model, the deliverable"]
        Audit["FoodPulse live audit<br/>23 of 23, Phase 6 lab audit"]
        RedisDrill["Redis failover drill<br/>redis-failover-drill.sh<br/>Executed and documented"]
        PGDrill["PostgreSQL failover drill<br/>pg-failover-drill.sh<br/>Procedure documented"]
        ClusterStatus["cluster-status.sh<br/>Proxy, dependency, and<br/>application health together"]
        RedisDrill --> DataRedis
        PGDrill --> DataPG
        ClusterStatus --> Cluster
        Audit --> Cluster
    end

    User --> CF
    CF --> Traefik
    Traefik --> UI
    UI --> API
    API --> HAProxyPG_L
    API --> HAProxyRedis_L
    HAProxyPG_L --> PGPrimary
    HAProxyRedis_L --> RedisMaster
    API -->|"Kubernetes path"| PGPrimary
    API -->|"Kubernetes path,<br/>Sentinel aware"| RedisMaster

    App -->|"metrics and logs"| Prom
    DataPG -->|"health signals"| Prom
    DataRedis -->|"health signals"| Prom
    Prom --> Operator
    ControlPlane --> Operator
```

## Flow diagram: a failover drill, Mermaid source

```mermaid
flowchart LR
    A["Trigger the failure<br/>Bounded drill script"] --> B["Observe together<br/>HAProxy backend state,<br/>application behaviour,<br/>dependency health"]
    B --> C["Run the failover procedure<br/>Sentinel promotion or<br/>PostgreSQL failover"]
    C --> D["Validate application impact<br/>User facing side,<br/>not only the database"]
    D --> E["Validate recovery<br/>And record the drill<br/>against telemetry"]
    E --> F["Drill record joins<br/>the platform incident set"]
```

## Notes

- Lab environment. Failover results demonstrate procedure and behaviour at lab scale, not production load or multi site resilience.
- Audit counts are point in time lab validation results documented in the platform repository.
- Live application: `https://foodpulse.eseosadevbox.com`.
