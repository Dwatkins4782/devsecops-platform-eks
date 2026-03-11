# Interview Prep: Senior DevOps Engineer — OX Security

## Role Summary
- Company: OX Security (application security company)
- Role: Senior DevOps Engineer
- Location: Remote
- Focus: Infrastructure at scale for security solutions, CI/CD, Kubernetes, multi-cloud

---

## Section 1: Kubernetes Deep Dive

### Q: "Explain the difference between EKS, AKS, and GKE. Which do you prefer and why?"

**Answer:**

| Feature | EKS (AWS) | AKS (Azure) | GKE (Google) |
|---------|-----------|-------------|--------------|
| Control plane cost | $0.10/hr (~$73/mo) | Free | Free (Standard), $0.10/hr (Autopilot) |
| CNI | VPC-CNI (native) | Azure CNI or Kubenet | GKE-managed (native) |
| Identity | IRSA (OIDC) | Workload Identity (AAD) | Workload Identity (GCP SA) |
| Auto-scaling | Karpenter or Cluster Autoscaler | KEDA + Cluster Autoscaler | Autopilot (fully managed) |
| Network Policy | Calico (addon) | Calico or Azure NPM | Dataplane V2 (native) |
| Upgrades | Manual or managed | Auto-upgrade channels | Release channels (rapid/regular/stable) |

"I have the deepest experience with EKS, but I'm proficient across all three. For a security company like OX, I'd prioritize whichever the customers are predominantly on — security tools need to integrate tightly with the customer's cloud."

### Q: "Describe Kubernetes internals you've worked with."

**Key areas:**
- **API Server**: Authentication (OIDC, webhook token), authorization (RBAC, ABAC), admission controllers (mutating/validating webhooks — this is how OPA Gatekeeper works)
- **Scheduler**: Node affinity, taints/tolerations, pod topology spread constraints, priority classes
- **etcd**: Backup/restore, encryption at rest, defragmentation, cluster health monitoring
- **Kubelet**: Pod lifecycle, container runtime interface (CRI), resource management (cgroups), node status reporting
- **Container Runtime**: containerd (standard), CRI-O, gVisor/Kata for sandbox isolation (relevant for security workloads)
- **Networking**: CNI plugins (Calico, Cilium), kube-proxy (iptables vs IPVS), Service mesh (Istio, Linkerd), DNS (CoreDNS)

### Q: "How do you handle Kubernetes security?"

**Answer (defense-in-depth):**

1. **Cluster level**: Private API endpoint, OIDC authentication, RBAC with least privilege, audit logging enabled, secrets encryption with KMS
2. **Node level**: CIS benchmarks (kube-bench), encryption at host, auto-patching, node restriction admission plugin
3. **Pod level**: Pod Security Standards (restricted profile), no privileged containers, read-only root filesystem, non-root users, seccomp profiles
4. **Network level**: Default deny NetworkPolicies, namespace isolation, service mesh mTLS
5. **Container level**: Image scanning (Trivy), signed images, no `:latest` tag, approved registry allowlist
6. **Runtime level**: Falco for anomaly detection, eBPF-based monitoring, syscall filtering

"For a security company, I'd implement all of these plus runtime security monitoring with Falco feeding into a SIEM for correlation."

---

## Section 2: CI/CD Pipeline Architecture

### Q: "Design a CI/CD pipeline for a security product."

**Answer:**

```
Developer Push → GitHub Actions / GitLab CI
    │
    ├── Lint (tflint, hadolint, yamllint, eslint)
    ├── Secret Detection (gitleaks, trufflehog)
    ├── SAST (Semgrep, CodeQL)
    ├── Unit Tests
    │
    ▼
Build Stage
    ├── Docker build (multi-stage, distroless base)
    ├── Container scan (Trivy — CVE + misconfig)
    ├── Sign image (cosign/Notation)
    ├── Push to ECR/ACR/GAR
    │
    ▼
Deploy to Dev (ArgoCD sync)
    ├── Terraform plan + apply (dev)
    ├── Integration tests
    ├── DAST scan (OWASP ZAP)
    │
    ▼
Promote to Staging (ArgoCD sync)
    ├── Load testing (k6)
    ├── Chaos engineering (Litmus)
    ├── Security regression tests
    │
    ▼
Promote to Prod (manual approval)
    ├── Canary deployment (Argo Rollouts)
    ├── Monitoring (Prometheus + Grafana)
    ├── Automated rollback on SLO breach
```

"Key principle: shift-left security. Every scan happens before code reaches production. For a security company, our own pipeline must be exemplary."

### Q: "How do you handle GitOps with ArgoCD?"

**Answer:**
"ArgoCD watches a Git repository for Kubernetes manifests or Helm charts. When a change is pushed:

1. ArgoCD detects the diff between Git (desired state) and cluster (actual state)
2. It auto-syncs or waits for manual approval (configurable per environment)
3. It applies changes with configurable sync strategies (apply, hook, prune)
4. It monitors health and rollback on failure

I configure ArgoCD with:
- **App-of-Apps pattern**: A root Application that manages other Applications
- **ApplicationSets**: Template-based generation for multi-cluster deployments
- **Sync waves**: Ordered deployment (CRDs first, then operators, then apps)
- **SSO via OIDC**: Azure AD / Google / Okta for developer access
- **RBAC**: Project-based access control (dev team sees dev apps only)"

---

## Section 3: Monitoring & Observability

### Q: "Design a monitoring stack for a security platform."

**Answer:**

```
Metrics: Prometheus → Thanos (long-term storage) → Grafana
Logs: Fluent Bit → Elasticsearch/Loki → Grafana
Traces: OpenTelemetry → Jaeger/Tempo → Grafana
Alerts: Alertmanager → PagerDuty / Slack / OpsGenie
Security: Falco → Falco Sidekick → SIEM (Splunk/Sentinel)
```

**Key dashboards I'd build:**
1. **Platform health**: Node utilization, pod status, API server latency
2. **Security overview**: Vulnerability counts by severity, policy violations, failed auth attempts
3. **CI/CD metrics**: Deployment frequency, lead time, change failure rate, MTTR (DORA metrics)
4. **SLO dashboard**: Error budget, availability, latency percentiles

### Q: "What's your experience with Prometheus?"

**Cover:**
- PromQL queries (rate, histogram_quantile, aggregation)
- Recording rules for pre-computed expensive queries
- Alerting rules with severity-based routing
- Service discovery (Kubernetes SD, EC2 SD)
- Federation for multi-cluster
- Thanos or Cortex for long-term storage
- Custom exporters for application-specific metrics

---

## Section 4: Infrastructure as Code

### Q: "How do you structure Terraform for multi-environment deployments?"

**Answer:**
"I use a modules + environments pattern with Terragrunt:

```
terraform/
├── modules/           # Reusable, versioned modules
│   ├── eks-cluster/
│   ├── networking/
│   └── monitoring/
├── environments/
│   ├── dev/
│   │   └── terragrunt.hcl    # DRY config, inherits from root
│   ├── staging/
│   │   └── terragrunt.hcl
│   └── prod/
│       └── terragrunt.hcl
└── terragrunt.hcl     # Root config (backend, provider)
```

Terragrunt handles:
- **DRY backends**: Auto-generates S3/GCS bucket + DynamoDB/GCS lock per environment
- **Dependency management**: `dependency` blocks ensure networking deploys before EKS
- **Input inheritance**: Common values defined once in root, overridden per environment
- **Run-all**: `terragrunt run-all plan` across all environments

I also use **Helm** for Kubernetes-native deployments and **ArgoCD** for GitOps."

### Q: "How do you handle Helm chart management?"

**Answer:**
- Version-pin all charts in `Chart.lock`
- Override values per environment via values files
- Use Helmfile or ArgoCD for declarative management
- Store custom charts in a private Helm registry (ECR, ACR, ChartMuseum)
- Template testing with `helm template` + `kubeval`/`kubeconform`

---

## Section 5: Security Concepts

### Q: "What security principles guide your infrastructure design?"

**Answer (relevant for OX Security):**

1. **Zero Trust**: Never trust, always verify. No implicit trust based on network location.
2. **Defense in Depth**: Multiple layers of security controls.
3. **Least Privilege**: Minimal permissions needed for each component.
4. **Immutable Infrastructure**: Replace, don't patch. Container images are immutable, deployments are blue/green.
5. **Shift Left**: Security scanning in CI, not after deployment.
6. **Supply Chain Security**: Sign images, verify provenance, SBOM generation, dependency scanning.

### Q: "How do you secure the software supply chain?"

**Answer (critical for a security company):**

1. **Source**: Branch protection, signed commits, code review requirements
2. **Build**: Hermetic builds, SLSA Level 3 compliance, build provenance attestation
3. **Dependencies**: Dependabot/Renovate for updates, SCA scanning (Snyk, npm audit)
4. **Containers**: Multi-stage builds, distroless/scratch base images, no secrets in layers
5. **Registry**: Image signing with cosign, admission webhook to verify signatures
6. **Runtime**: Read-only filesystem, non-root, resource limits, network policies

---

## Section 6: Scripting & Automation

### Q: "Describe a complex automation you've built."

**Answer (reference your project):**
"I built an automated incident response system in Python that:
1. Watches Kubernetes events for security anomalies (via the Kubernetes Python client)
2. Quarantines compromised pods by applying a deny-all NetworkPolicy
3. Captures forensic data (pod spec, logs, container state) before termination
4. Notifies the security team via Slack webhook and creates a JIRA ticket via REST API
5. All actions are logged to an immutable audit trail

This reduced our incident response time from 30+ minutes (manual) to under 2 minutes (automated)."

### Q: "What's your approach to writing production scripts?"

**Principles:**
- **Idempotent**: Safe to run multiple times
- **Error handling**: `set -euo pipefail` in Bash, try/except in Python
- **Logging**: Structured logging (JSON) for machine parsing
- **Testing**: Unit tests for Python, shellcheck for Bash
- **Configuration**: Environment variables or config files, never hardcoded
- **Documentation**: Usage section, examples, prerequisites

---

## Section 7: Behavioral Questions

### Q: "How do you collaborate with cross-functional teams?"

**Answer:**
"At a security company, DevOps sits at the intersection of engineering, security, and operations. I:
- **With developers**: Provide self-service CI/CD pipelines, paved roads that are secure by default
- **With security**: Implement their policies as code (OPA, network policies), ensure scanning is automated
- **With operations**: Build observability, runbooks, and automated incident response
- **Communication**: I document decisions in ADRs, create runbooks for common operations, and hold weekly sync calls"

### Q: "How do you stay current with DevOps and security trends?"

**Relevant for OX:**
- CNCF ecosystem (KubeCon talks, CNCF landscape)
- OWASP Top 10, SLSA framework, NIST guidelines
- Security advisories (GitHub Advisory Database, NVD)
- Hands-on: Run personal clusters, contribute to open-source tooling

---

## Questions to Ask the Interviewer

1. What cloud providers do your customers primarily use?
2. What's the current Kubernetes platform (EKS/AKS/GKE/self-managed)?
3. What CI/CD tooling is in place today?
4. How does the DevOps team interact with the product security team?
5. What's the biggest infrastructure challenge you're facing right now?
6. What does on-call look like for this role?
7. How do you handle multi-tenancy for customer deployments?
8. What's the team size and structure?
9. What's the deployment frequency?
10. Are there any compliance frameworks (SOC 2, ISO 27001) you're working toward?
