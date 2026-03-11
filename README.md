# DevSecOps Platform -- Multi-Cloud Security Infrastructure

Production-grade DevSecOps platform built on Amazon EKS with comprehensive security tooling,
GitOps-driven deployments, and full observability. Designed to demonstrate enterprise-level
infrastructure engineering, security automation, and operational excellence.

---

## Architecture Overview

```
                            +---------------------------+
                            |     GitHub Actions        |
                            |  CI/CD Pipeline           |
                            |  (Lint/Scan/Build/Deploy) |
                            +------------+--------------+
                                         |
                                         | GitOps Sync
                                         v
                    +--------------------+--------------------+
                    |              ArgoCD (GitOps)            |
                    |        Continuous Delivery Engine       |
                    +--------------------+--------------------+
                                         |
          +------------------------------+-------------------------------+
          |                              |                               |
          v                              v                               v
+-------------------+      +-------------------------+      +---------------------+
|  Security Tools   |      |    EKS Cluster (prod)   |      |   Monitoring Stack  |
|                   |      |                         |      |                     |
|  - Falco          |      |  +-------------------+  |      |  - Prometheus       |
|  - Trivy Operator |      |  | Worker Nodes (ASG)|  |      |  - Grafana          |
|  - OPA Gatekeeper |      |  | t3.xlarge x 3-10  |  |      |  - Alertmanager     |
|  - Pod Security   |      |  +-------------------+  |      |  - CloudWatch       |
|  - Network Policy |      |  | OIDC / IRSA       |  |      |  - Loki (Logs)      |
+-------------------+      |  | KMS Encryption    |  |      +---------------------+
                            |  | Calico CNI        |  |
                            |  +-------------------+  |
                            +-------------------------+
                                         |
          +------------------------------+-------------------------------+
          |                              |                               |
          v                              v                               v
+-------------------+      +-------------------------+      +---------------------+
|  VPC / Networking |      |   IAM / Identity        |      |  Secrets / KMS      |
|                   |      |                         |      |                     |
|  - 3 AZ Subnets   |      |  - Least Privilege      |      |  - Envelope Encrypt |
|  - Public/Private |      |  - IRSA (Pod Identity)  |      |  - Secrets Manager  |
|  - NAT Gateway    |      |  - OIDC Federation      |      |  - etcd Encryption  |
|  - VPC Flow Logs  |      |  - Node IAM Roles       |      |  - KMS Key Rotation |
|  - Route Tables   |      +-------------------------+      +---------------------+
+-------------------+

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
|   |-- modules/
|   |   |-- eks-cluster/          # EKS cluster with encryption, OIDC, IRSA
|   |   |-- networking/           # VPC, subnets, NAT, flow logs
|   |   |-- monitoring/           # Prometheus, Grafana, Alertmanager
|   |   +-- security-tools/       # Falco, Trivy, OPA Gatekeeper
|   +-- environments/
|       +-- prod/                 # Production root module + Terragrunt
|-- kubernetes/
|   |-- argocd/                   # ArgoCD Application CRDs and values
|   |-- security-policies/        # Pod security, network policies, OPA
|   +-- monitoring/               # Prometheus rules, Grafana dashboards
|-- ci-cd/
|   +-- github-actions/           # Multi-stage CI/CD pipeline
|-- scripts/                      # Security audit and incident response
+-- docs/                         # Architecture and runbook documentation
```

---

## Skills and Technologies

| Category             | Technology                        | Purpose                                      |
|----------------------|-----------------------------------|----------------------------------------------|
| **Orchestration**    | Amazon EKS (Kubernetes 1.29)      | Container orchestration and workload runtime  |
| **IaC**              | Terraform + Terragrunt            | Infrastructure provisioning and state mgmt    |
| **GitOps**           | ArgoCD                            | Declarative continuous delivery               |
| **CI/CD**            | GitHub Actions                    | Build, test, scan, and deployment automation  |
| **Monitoring**       | Prometheus + Grafana              | Metrics collection and visualization          |
| **Alerting**         | Alertmanager + CloudWatch         | Incident notification and escalation          |
| **Runtime Security** | Falco                             | Real-time threat detection via syscall audit  |
| **Image Scanning**   | Trivy Operator                    | Continuous vulnerability scanning in-cluster  |
| **Policy Engine**    | OPA Gatekeeper                    | Kubernetes admission control policies         |
| **Networking**       | Calico CNI + Network Policies     | Pod-level network segmentation                |
| **Encryption**       | AWS KMS                           | Envelope encryption for etcd and secrets      |
| **Identity**         | IRSA (IAM Roles for SAs)          | Pod-level AWS IAM with OIDC federation        |
| **Logging**          | VPC Flow Logs + CloudWatch Logs   | Network and application log aggregation       |
| **Scripting**        | Bash + Python                     | Security auditing and incident response       |

---

## Quick Start

### Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Terraform >= 1.6.0
- Terragrunt >= 0.54.0
- kubectl >= 1.29
- Helm >= 3.14
- ArgoCD CLI (optional)

### Deploy Infrastructure

```bash
# Initialize and deploy with Terragrunt
cd terraform/environments/prod
terragrunt init
terragrunt plan -out=tfplan
terragrunt apply tfplan

# Configure kubectl
aws eks update-kubeconfig --name devsecops-prod-cluster --region us-east-1

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

### Deploy Security Tools

```bash
# ArgoCD handles deployment via GitOps
# Verify ArgoCD applications
kubectl get applications -n argocd

# Manual security audit
chmod +x scripts/security-audit.sh
./scripts/security-audit.sh
```

---

## Security Features

- **Defense in Depth**: Multiple layers of security controls from network to runtime
- **Zero Trust Networking**: Default-deny network policies with explicit allow rules
- **Immutable Infrastructure**: Container images are scanned and signed before deployment
- **Least Privilege IAM**: IRSA provides pod-level AWS permissions via OIDC federation
- **Encryption at Rest**: KMS-managed encryption for etcd, EBS volumes, and secrets
- **Runtime Protection**: Falco monitors syscalls for anomalous behavior in real time
- **Policy Enforcement**: OPA Gatekeeper enforces admission policies at the API server
- **Continuous Scanning**: Trivy operator scans running workloads for vulnerabilities
- **Audit Logging**: CloudWatch and VPC flow logs provide full audit trail

---

## Monitoring and Alerting

Prometheus collects metrics from all cluster components and security tools.
Grafana provides dashboards for security posture, cluster health, and resource utilization.
Alertmanager routes critical alerts to Slack and PagerDuty.

Key alert categories:
- Falco runtime security events (critical severity)
- OPA policy violations and audit failures
- Trivy vulnerability scan results (HIGH/CRITICAL)
- Node resource exhaustion and pod eviction
- Certificate expiration warnings
- Unauthorized API server access attempts

---

## License

MIT License. See LICENSE for details.
