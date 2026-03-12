# DevSecOps Platform -- Multi-Environment Security Infrastructure

Production-grade DevSecOps platform built on Amazon EKS with comprehensive security tooling,
GitOps-driven deployments, and full observability. Supports **multi-environment promotion**
(dev → staging → prod) with environment-specific configurations managed through
Terragrunt, Kustomize, and ArgoCD ApplicationSets.

> **New here?** Read the [Multi-Environment Guide](docs/MULTI-ENV-GUIDE.md) for a complete
> beginner-friendly walkthrough of how everything connects.

---

## Architecture Overview

```
                            +---------------------------+
                            |     GitHub Actions        |
                            |  CI/CD Pipeline           |
                            |  (Lint/Scan/Build/Deploy) |
                            +------------+--------------+
                                         |
                      Branch-based routing (matrix strategy):
                      develop → DEV | staging → STAGING | main → PROD
                                         |
                    +--------------------+--------------------+
                    |              ArgoCD (GitOps)            |
                    |   ApplicationSets auto-generate apps    |
                    |   per environment from templates        |
                    +--------------------+--------------------+
                                         |
          +------------------------------+-------------------------------+
          |                              |                               |
          v                              v                               v
+-------------------+      +-------------------------+      +---------------------+
|  Security Tools   |      | EKS Clusters (per env)  |      |   Monitoring Stack  |
|                   |      |                         |      |                     |
|  - Falco          |      |  DEV:  1x t3.medium     |      |  - Prometheus       |
|  - Trivy Operator |      |  STG:  2x t3.large      |      |  - Grafana          |
|  - OPA Gatekeeper |      |  PROD: 3x t3.xlarge     |      |  - Alertmanager     |
|  - Pod Security   |      |                         |      |  - CloudWatch       |
|  - Network Policy |      |  OIDC / IRSA / KMS      |      |  - Loki (Logs)      |
+-------------------+      +-------------------------+      +---------------------+

Data Flow:
  Developer --> GitHub --> Actions CI --> ECR --> ArgoCD --> EKS
                                |                            |
                                +-- Security Scans           +-- Falco Runtime Detection
                                +-- SAST/DAST                +-- OPA Policy Enforcement
                                +-- Container Scanning       +-- Network Policy Isolation
```

---

## Project Structure

```
devsecops-platform-eks/
|-- terraform/
|   |-- terragrunt.hcl                  # Root config (shared by all environments)
|   |-- _envcommon/                     # Shared module configurations
|   |   |-- networking.hcl
|   |   |-- eks-cluster.hcl
|   |   |-- monitoring.hcl
|   |   +-- security-tools.hcl
|   |-- modules/
|   |   |-- eks-cluster/                # EKS cluster with encryption, OIDC, IRSA
|   |   |-- networking/                 # VPC, subnets, NAT, flow logs
|   |   |-- monitoring/                 # Prometheus, Grafana, Alertmanager
|   |   +-- security-tools/             # Falco, Trivy, OPA Gatekeeper
|   +-- environments/
|       |-- dev/                        # Dev: t3.medium, 1 node, warn-only
|       |   |-- env.hcl
|       |   +-- terragrunt.hcl
|       |-- staging/                    # Staging: t3.large, 2 nodes, mixed
|       |   |-- env.hcl
|       |   +-- terragrunt.hcl
|       +-- prod/                       # Prod: t3.xlarge, 3+ nodes, strict
|           |-- env.hcl
|           |-- terragrunt.hcl
|           +-- main.tf                 # Shared Terraform code (all envs use this)
|
|-- kubernetes/
|   |-- base/                           # Kustomize base (production-grade defaults)
|   |   |-- security-policies/          # Pod security, network policies, OPA
|   |   +-- monitoring/                 # Prometheus rules, Grafana dashboards
|   |-- overlays/                       # Per-environment Kustomize patches
|   |   |-- dev/                        # All OPA → warn, relaxed alerts
|   |   |-- staging/                    # Mixed OPA, moderate alerts
|   |   +-- prod/                       # Uses base as-is (strictest)
|   +-- argocd/                         # ArgoCD GitOps configuration
|       |-- appproject.yaml             # Project security boundary + RBAC
|       |-- applicationsets.yaml        # Auto-generates apps per environment
|       |-- argocd-values.yaml          # Base Helm values for ArgoCD
|       +-- helm-values/               # Per-env ArgoCD configuration
|           |-- values-dev.yaml
|           |-- values-staging.yaml
|           +-- values-prod.yaml
|
|-- ci-cd/
|   +-- github-actions/
|       +-- ci-pipeline.yml             # Multi-env pipeline with matrix strategy
|
|-- scripts/                            # Security audit and incident response
|   |-- security-audit.sh
|   +-- incident-response.py
|
+-- docs/
    |-- MULTI-ENV-GUIDE.md              # Comprehensive beginner guide
    +-- INTERVIEW-PREP-SR-DEVOPS-ENGINEER.md
```

---

## Multi-Environment Strategy

### Environment Promotion Flow

```
develop branch  ──→  DEV cluster   ──→  Test & iterate
                         |
staging branch  ──→  STAGING cluster ──→  Pre-production validation
                         |
main branch     ──→  PROD cluster  ──→  Live traffic
```

### Configuration Layers

| Layer | Tool | Purpose | Where |
|-------|------|---------|-------|
| **Infrastructure** | Terragrunt | VPC, EKS, nodes per env | `terraform/environments/` |
| **K8s Policies** | Kustomize | OPA, NetworkPolicy per env | `kubernetes/overlays/` |
| **GitOps Delivery** | ArgoCD ApplicationSet | Auto-deploy per env | `kubernetes/argocd/` |
| **ArgoCD Config** | Helm Values | ArgoCD itself per env | `kubernetes/argocd/helm-values/` |
| **CI/CD** | GitHub Actions Matrix | Build & deploy per env | `ci-cd/github-actions/` |

### Key Differences by Environment

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Node type | t3.medium | t3.large | t3.xlarge |
| Nodes (min/max) | 1/3 | 2/5 | 3/10 |
| OPA enforcement | All warn | Mixed | All deny |
| Alert thresholds | Relaxed | Moderate | Tight |
| ArgoCD self-heal | Off | Off | On |
| Git branch | develop | staging | main |

---

## Skills and Technologies

| Category             | Technology                        | Purpose                                      |
|----------------------|-----------------------------------|----------------------------------------------|
| **Orchestration**    | Amazon EKS (Kubernetes 1.29)      | Container orchestration and workload runtime  |
| **IaC**              | Terraform + Terragrunt            | Infrastructure provisioning and state mgmt    |
| **GitOps**           | ArgoCD + ApplicationSets          | Declarative continuous delivery               |
| **CI/CD**            | GitHub Actions (Matrix Strategy)  | Multi-env build, test, scan, and deployment   |
| **Monitoring**       | Prometheus + Grafana              | Metrics collection and visualization          |
| **Alerting**         | Alertmanager + CloudWatch         | Incident notification and escalation          |
| **Runtime Security** | Falco                             | Real-time threat detection via syscall audit  |
| **Image Scanning**   | Trivy Operator                    | Continuous vulnerability scanning in-cluster  |
| **Policy Engine**    | OPA Gatekeeper                    | Kubernetes admission control policies         |
| **K8s Customization**| Kustomize (Base + Overlays)       | Per-environment manifest patching             |
| **Networking**       | Calico CNI + Network Policies     | Pod-level network segmentation                |
| **Encryption**       | AWS KMS                           | Envelope encryption for etcd and secrets      |
| **Identity**         | IRSA (IAM Roles for SAs)          | Pod-level AWS IAM with OIDC federation        |

---

## Quick Start

### Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Terraform >= 1.6.0
- Terragrunt >= 0.54.0
- kubectl >= 1.29
- Helm >= 3.14
- ArgoCD CLI (optional)

### Deploy a Single Environment

```bash
# Deploy dev infrastructure
cd terraform/environments/dev
terragrunt init
terragrunt plan -out=tfplan
terragrunt apply tfplan

# Configure kubectl
aws eks update-kubeconfig --name devsecops-dev-cluster --region us-east-1

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

### Deploy All Environments

```bash
cd terraform
terragrunt run-all plan      # Plan all environments in parallel
terragrunt run-all apply     # Apply all environments
```

### Preview Kustomize Output

```bash
# See what dev produces
kubectl kustomize kubernetes/overlays/dev/

# See what prod produces
kubectl kustomize kubernetes/overlays/prod/

# Compare dev vs prod
diff <(kubectl kustomize kubernetes/overlays/dev/) \
     <(kubectl kustomize kubernetes/overlays/prod/)
```

---

## Security Features

- **Defense in Depth**: Multiple layers of security controls from network to runtime
- **Zero Trust Networking**: Default-deny network policies with explicit allow rules
- **Progressive Enforcement**: Policies warn in dev, deny in prod
- **Immutable Infrastructure**: Container images are scanned and signed before deployment
- **Least Privilege IAM**: IRSA provides pod-level AWS permissions via OIDC federation
- **Encryption at Rest**: KMS-managed encryption for etcd, EBS volumes, and secrets
- **Runtime Protection**: Falco monitors syscalls for anomalous behavior in real time
- **Policy Enforcement**: OPA Gatekeeper enforces admission policies at the API server
- **Continuous Scanning**: Trivy operator scans running workloads for vulnerabilities
- **Audit Logging**: CloudWatch and VPC flow logs provide full audit trail

---

## Documentation

- [Multi-Environment Guide](docs/MULTI-ENV-GUIDE.md) — Complete beginner walkthrough
- [Interview Prep](docs/INTERVIEW-PREP-SR-DEVOPS-ENGINEER.md) — DevOps interview preparation

---

## License

MIT License. See LICENSE for details.
