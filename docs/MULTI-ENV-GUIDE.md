# Multi-Environment Guide: From Zero to Production

> **Who is this for?** If you're new to multi-environment infrastructure and need to understand how dev/staging/prod environments work together, this guide explains everything from the ground up. No prior knowledge of Terragrunt, Kustomize, or ArgoCD is assumed.

---

## Table of Contents

1. [Why Multiple Environments?](#1-why-multiple-environments)
2. [Architecture Overview](#2-architecture-overview)
3. [The Big Picture: What Calls What](#3-the-big-picture-what-calls-what)
4. [Layer 1: Terragrunt (Infrastructure)](#4-layer-1-terragrunt-infrastructure)
5. [Layer 2: Kustomize (Kubernetes Manifests)](#5-layer-2-kustomize-kubernetes-manifests)
6. [Layer 3: ArgoCD ApplicationSet (GitOps Delivery)](#6-layer-3-argocd-applicationset-gitops-delivery)
7. [Layer 4: Helm Values (ArgoCD's Own Config)](#7-layer-4-helm-values-argocds-own-config)
8. [Layer 5: CI/CD Pipeline (GitHub Actions)](#8-layer-5-cicd-pipeline-github-actions)
9. [Complete Flow Walkthrough](#9-complete-flow-walkthrough)
10. [File-by-File Reference](#10-file-by-file-reference)
11. [Common Operations Runbook](#11-common-operations-runbook)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Why Multiple Environments?

### The Problem

Imagine you have one Kubernetes cluster running your production application. A developer writes new code and deploys it directly to production. If there's a bug, real users are affected immediately.

### The Solution: Environment Promotion

Instead of deploying directly to production, changes flow through a series of environments:

```
   DEV                    STAGING                PRODUCTION
   (playground)           (dress rehearsal)       (real users)

   - Break things freely  - Mirrors production   - Maximum stability
   - Quick iteration      - Catch issues early   - Strict security
   - Loose security       - Moderate security    - Full monitoring
   - 1 node, small        - 2 nodes, medium      - 3+ nodes, large
```

**Think of it like theater:** Dev is rehearsal in your living room, staging is dress rehearsal on the actual stage, and production is opening night with a full audience.

### What's Different Between Environments?

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| **Server size** | t3.medium (small) | t3.large (medium) | t3.xlarge (large) |
| **Number of servers** | 1 | 2-5 | 3-10 |
| **VPC network range** | 10.10.0.0/16 | 10.20.0.0/16 | 10.0.0.0/16 |
| **Security policies** | Warn only | Mixed (warn + deny) | All enforced (deny) |
| **Alert sensitivity** | Very relaxed | Moderate | Tight |
| **Auto-healing** | Off | Off | On |
| **Git branch watched** | `develop` | `staging` | `main` |

---

## 2. Architecture Overview

Here's how all the pieces fit together. Don't worry if this seems complex — we'll explain each layer below.

```
  DEVELOPER writes code
       |
       | git push to branch
       v
  +------------------+
  | GitHub Actions   |  <-- CI/CD Pipeline (ci-pipeline.yml)
  | CI/CD Pipeline   |      Runs: lint, security scan, build, deploy
  +--------+---------+
           |
           | 1. Runs Terragrunt       2. Syncs ArgoCD
           |    (creates AWS infra)      (deploys K8s manifests)
           v                             v
  +------------------+         +------------------+
  | Terragrunt       |         | ArgoCD           |
  | (Infrastructure) |         | (GitOps Engine)  |
  |                  |         |                  |
  | Creates:         |         | Deploys:         |
  | - VPC & Subnets  |         | - OPA Policies   |
  | - EKS Cluster    |         | - Network Policies|
  | - Node Groups    |         | - Prometheus Rules|
  | - Security Tools |         | - Grafana Dashboards|
  +--------+---------+         +--------+---------+
           |                             |
           | Which env?                  | Which overlay?
           v                             v
  +------------------+         +------------------+
  | env.hcl          |         | Kustomize        |
  | (per-env values) |         | (per-env patches)|
  |                  |         |                  |
  | dev/env.hcl      |         | overlays/dev/    |
  | staging/env.hcl  |         | overlays/staging/|
  | prod/env.hcl     |         | overlays/prod/   |
  +------------------+         +------------------+
```

**Key Insight:** There are TWO separate systems managing different things:
1. **Terragrunt** manages AWS infrastructure (VPC, EKS cluster, node groups)
2. **ArgoCD + Kustomize** manages what runs ON the cluster (policies, monitoring)

---

## 3. The Big Picture: What Calls What

This is the most important section. Here's the exact chain of "what calls what" for each system:

### Infrastructure Chain (Terragrunt)

```
You type: cd terraform/environments/dev && terragrunt plan

  Step 1: Terragrunt reads dev/terragrunt.hcl
          |
          | "include root" directive
          v
  Step 2: Terragrunt walks up directories, finds terraform/terragrunt.hcl (root)
          |
          | Root reads dev/env.hcl (via find_in_parent_folders)
          v
  Step 3: Root config sets up:
          - S3 backend bucket: "devsecops-tfstate-dev"
          - AWS provider for us-east-1
          - Provider version locks
          |
          | "terraform.source" in dev/terragrunt.hcl
          v
  Step 4: Terragrunt finds the Terraform code at environments/prod/main.tf
          (dev REUSES prod's Terraform code — it's parameterized!)
          |
          | "inputs" block in dev/terragrunt.hcl
          v
  Step 5: Terragrunt passes dev-specific variable values:
          vpc_cidr = "10.10.0.0/16"
          node_instance_types = ["t3.medium"]
          node_desired_size = 1
          |
          | main.tf calls modules
          v
  Step 6: Terraform modules create AWS resources:
          module "networking"     → VPC, subnets, NAT
          module "eks_cluster"    → EKS cluster, node group
          module "monitoring"     → Prometheus, Grafana
          module "security_tools" → Falco, Trivy, OPA
```

### Kubernetes Manifests Chain (ArgoCD + Kustomize)

```
ArgoCD ApplicationSet Controller watches for ApplicationSet resources

  Step 1: Reads applicationsets.yaml
          |
          | List generator with 3 environments
          v
  Step 2: Creates 6 ArgoCD Applications automatically:
          - security-policies-dev    (watches develop branch)
          - security-policies-staging (watches staging branch)
          - security-policies-prod    (watches main branch)
          - monitoring-configs-dev
          - monitoring-configs-staging
          - monitoring-configs-prod
          |
          | Each Application points to a Kustomize overlay path
          v
  Step 3: ArgoCD clones the Git repo and runs kustomize build
          Example for dev:
            kustomize build kubernetes/overlays/dev/
          |
          | Kustomize reads overlays/dev/kustomization.yaml
          v
  Step 4: kustomization.yaml says:
          resources:
            - ../../base/security-policies   ← "Start with base"
            - ../../base/monitoring          ← "Include monitoring too"
          patches:
            - (change OPA from deny to warn) ← "Then relax these"
          |
          | Base kustomization.yaml lists the actual YAML files
          v
  Step 5: Kustomize loads base resources:
          - pod-security.yaml
          - network-policies.yaml
          - opa-constraints.yaml
          - prometheus-rules.yaml
          |
          | Apply dev patches on top
          v
  Step 6: Kustomize outputs final merged YAML
          (base resources + dev modifications)
          |
          | ArgoCD applies to cluster
          v
  Step 7: kubectl apply → Resources created in Kubernetes
```

### CI/CD Chain (GitHub Actions)

```
Developer pushes to 'develop' branch

  Step 1: GitHub detects push, triggers ci-pipeline.yml
          |
          | Pipeline stages run sequentially
          v
  Step 2: LINT → Terraform fmt check, kubectl lint, YAML lint
          |
          v
  Step 3: SECURITY SCAN → tfsec, Checkov, Trivy, Kubescape, Gitleaks
          |
          v
  Step 4: BUILD → Docker build, push to ECR, image vulnerability scan
          |
          | Matrix strategy kicks in
          v
  Step 5: DEPLOY matrix runs for all 3 envs, but branch-check step
          skips staging and prod (because we pushed to 'develop'):

          deploy-dev:     branch-check → MATCH → runs terragrunt + argocd
          deploy-staging: branch-check → SKIP (develop != staging)
          deploy-prod:    branch-check → SKIP (develop != main)
          |
          v
  Step 6: For dev only:
          - terragrunt apply (updates AWS infrastructure)
          - argocd app sync security-policies-dev
          - argocd app sync monitoring-configs-dev
          - Smoke tests
          - Slack notification
```

---

## 4. Layer 1: Terragrunt (Infrastructure)

### What is Terragrunt?

**Terraform** is a tool that creates cloud infrastructure (VPCs, servers, databases) from code. **Terragrunt** is a thin wrapper around Terraform that solves the "DRY" problem (Don't Repeat Yourself).

**The problem Terragrunt solves:** Without Terragrunt, you'd need to copy your entire Terraform code for each environment:
```
environments/
  dev/main.tf      ← Copy of prod with small changes
  staging/main.tf  ← Another copy with different changes
  prod/main.tf     ← The original
```

This means if you update `main.tf`, you have to update 3 copies. Terragrunt lets you write the code ONCE and inject different values per environment.

### How Our Terragrunt Hierarchy Works

```
terraform/
|-- terragrunt.hcl                  ← ROOT: Shared config for ALL environments
|-- _envcommon/                     ← Module-level shared configs
|   |-- networking.hcl              ← How to call the networking module
|   |-- eks-cluster.hcl             ← How to call the EKS module
|   |-- monitoring.hcl              ← How to call the monitoring module
|   +-- security-tools.hcl          ← How to call the security-tools module
+-- environments/
    |-- dev/
    |   |-- env.hcl                 ← Dev-specific variables
    |   +-- terragrunt.hcl          ← Dev entry point
    |-- staging/
    |   |-- env.hcl                 ← Staging-specific variables
    |   +-- terragrunt.hcl          ← Staging entry point
    +-- prod/
        |-- env.hcl                 ← Prod-specific variables
        |-- terragrunt.hcl          ← Prod entry point
        +-- main.tf                 ← The ACTUAL Terraform code (shared by all)
```

### The Inheritance Chain

Think of it like a family tree where children inherit from parents:

```
terraform/terragrunt.hcl (GRANDPARENT)
    |
    | Provides: S3 backend, provider versions, retry config
    |
    +-- environments/dev/terragrunt.hcl (CHILD)
    |       |
    |       | Inherits: everything from grandparent
    |       | Adds: dev-specific inputs (t3.medium, 1 node)
    |       | Points to: prod/main.tf (reuses the Terraform code)
    |
    +-- environments/staging/terragrunt.hcl (CHILD)
    |       |
    |       | Same pattern, but staging inputs (t3.large, 2 nodes)
    |
    +-- environments/prod/terragrunt.hcl (CHILD)
            |
            | Points to: "." (main.tf is right here)
            | Prod inputs: (t3.xlarge, 3 nodes)
```

### Key Terragrunt Concepts

**`include "root"`** — Tells Terragrunt to inherit config from a parent file:
```hcl
include "root" {
  path = find_in_parent_folders()
  # This walks UP the directory tree until it finds another terragrunt.hcl
  # From environments/dev/, it finds terraform/terragrunt.hcl
}
```

**`terraform.source`** — Where to find the actual Terraform code:
```hcl
terraform {
  # The "//" separator means "this is a Terraform source path"
  # dirname(find_in_parent_folders()) = terraform/ directory
  # //environments/prod = look in the prod directory for .tf files
  source = "${dirname(find_in_parent_folders())}//environments/prod"
}
```

**`inputs`** — Values passed to Terraform variables:
```hcl
inputs = {
  vpc_cidr = "10.10.0.0/16"  # This becomes var.vpc_cidr in Terraform
  node_desired_size = 1       # This becomes var.node_desired_size
}
```

**`env.hcl`** — Environment-specific variables read by the root config:
```hcl
# The root terragrunt.hcl reads this to know which environment it's in
locals {
  environment = "dev"        # Used in S3 bucket name: devsecops-tfstate-dev
  aws_region  = "us-east-1"  # Used in provider and backend config
  account_id  = "123456789012"
}
```

### How to Deploy an Environment

```bash
# Deploy dev infrastructure
cd terraform/environments/dev
terragrunt plan      # Preview changes (safe, read-only)
terragrunt apply     # Create/update resources (makes real changes!)

# Deploy staging infrastructure
cd terraform/environments/staging
terragrunt plan
terragrunt apply

# Deploy ALL environments at once (from root)
cd terraform
terragrunt run-all plan    # Plan all environments in parallel
terragrunt run-all apply   # Apply all (be careful!)
```

---

## 5. Layer 2: Kustomize (Kubernetes Manifests)

### What is Kustomize?

Kustomize is a tool built into `kubectl` that lets you customize Kubernetes YAML files without copying them. It uses a "base + overlay" pattern:

```
BASE (the original YAML files)
  +
OVERLAY (patches that modify specific fields)
  =
FINAL YAML (what gets applied to the cluster)
```

### Our Kustomize Structure

```
kubernetes/
|-- base/                              ← ORIGINAL files (production-grade)
|   |-- security-policies/
|   |   |-- kustomization.yaml         ← Lists which files are in this base
|   |   |-- pod-security.yaml          ← Namespace configs, RBAC, quotas
|   |   |-- network-policies.yaml      ← Zero-trust network rules
|   |   +-- opa-constraints.yaml       ← OPA Gatekeeper admission policies
|   +-- monitoring/
|       |-- kustomization.yaml
|       |-- prometheus-rules.yaml      ← Alert rules and thresholds
|       +-- grafana-dashboard-security.json
|
+-- overlays/                          ← PER-ENVIRONMENT modifications
    |-- dev/
    |   |-- kustomization.yaml         ← "Start with base, apply these patches"
    |   +-- patch-prometheus-rules.yaml ← Relaxed alert thresholds
    |-- staging/
    |   |-- kustomization.yaml
    |   +-- patch-prometheus-rules.yaml ← Moderately relaxed thresholds
    +-- prod/
        +-- kustomization.yaml         ← Uses base as-is (no patches!)
```

### How Kustomize Patches Work

**The base** has OPA constraints with `enforcementAction: deny` (the strictest setting):

```yaml
# In base/security-policies/opa-constraints.yaml
kind: K8sDisallowPrivileged
metadata:
  name: disallow-privileged-containers
spec:
  enforcementAction: deny    ← Blocks deployment of privileged containers
```

**The dev overlay** patches this to `warn` (lets it through but shows a warning):

```yaml
# In overlays/dev/kustomization.yaml
patches:
  - target:
      kind: K8sDisallowPrivileged
      name: disallow-privileged-containers
    patch: |-
      - op: replace
        path: /spec/enforcementAction
        value: warn    ← Changed from "deny" to "warn"
```

**The result** when you run `kustomize build overlays/dev/`:
```yaml
# Final output — base with patch applied
kind: K8sDisallowPrivileged
metadata:
  name: disallow-privileged-containers
spec:
  enforcementAction: warn    ← Dev gets "warn"
```

### Enforcement Levels by Environment

```
                    DEV (warn)     STAGING (mixed)    PROD (deny)
                    ──────────     ───────────────    ───────────
Required Labels     warn           deny               deny
Block Latest Tag    warn           deny               deny
Resource Limits     warn           deny               deny
No Privileged       warn           deny               deny
Non-Root User       warn           warn               warn*
Read-Only RootFS    warn           warn               warn*
Allowed Registries  warn           deny               deny

* These are "warn" even in prod base — future hardening target
```

### How to Preview Kustomize Output

```bash
# See what dev would produce (without applying)
kubectl kustomize kubernetes/overlays/dev/

# See what prod would produce
kubectl kustomize kubernetes/overlays/prod/

# Compare dev vs prod to see what's different
diff <(kubectl kustomize kubernetes/overlays/dev/) \
     <(kubectl kustomize kubernetes/overlays/prod/)
```

---

## 6. Layer 3: ArgoCD ApplicationSet (GitOps Delivery)

### What is ArgoCD?

ArgoCD is a **GitOps** tool. "GitOps" means: Git is the source of truth for what should run in your cluster. ArgoCD continuously compares what's in Git vs what's actually deployed, and automatically fixes any drift.

```
WITHOUT GitOps:                    WITH GitOps (ArgoCD):

Developer → kubectl apply → K8s   Developer → git push → GitHub
                                                            |
Problem: No audit trail,                                    v
anyone can change anything,        ArgoCD watches Git, auto-syncs
no rollback ability                to cluster. Full audit trail,
                                   easy rollback (git revert).
```

### What is an ApplicationSet?

An **Application** in ArgoCD represents one deployed thing. An **ApplicationSet** is a template that GENERATES multiple Applications automatically.

**Without ApplicationSet** (6 files to maintain):
```
security-policies-dev.yaml       ← 50 lines of YAML
security-policies-staging.yaml   ← 50 lines (nearly identical)
security-policies-prod.yaml      ← 50 lines (nearly identical)
monitoring-configs-dev.yaml      ← 50 lines
monitoring-configs-staging.yaml  ← 50 lines
monitoring-configs-prod.yaml     ← 50 lines
```

**With ApplicationSet** (2 files):
```
applicationsets.yaml             ← Contains 2 templates + 3 env entries each
                                    ArgoCD auto-generates all 6 Applications!
```

### How Our ApplicationSets Work

```yaml
# applicationsets.yaml (simplified)
spec:
  generators:
    - list:
        elements:
          - environment: dev
            targetRevision: develop          # Watch 'develop' branch
            overlayPath: kubernetes/overlays/dev
          - environment: staging
            targetRevision: staging          # Watch 'staging' branch
            overlayPath: kubernetes/overlays/staging
          - environment: prod
            targetRevision: main             # Watch 'main' branch
            overlayPath: kubernetes/overlays/prod

  template:
    metadata:
      name: "security-policies-{{environment}}"  # e.g., security-policies-dev
    spec:
      source:
        repoURL: https://github.com/Dwatkins4782/devsecops-platform-eks.git
        targetRevision: "{{targetRevision}}"      # develop, staging, or main
        path: "{{overlayPath}}"                   # Which Kustomize overlay
      destination:
        namespace: "{{environment}}"              # Deploy to dev/staging/prod namespace
```

ArgoCD processes this template 3 times (once per list element) and creates:

| Generated Application | Watches Branch | Kustomize Overlay |
|----------------------|----------------|-------------------|
| security-policies-dev | develop | overlays/dev/ |
| security-policies-staging | staging | overlays/staging/ |
| security-policies-prod | main | overlays/prod/ |

### The AppProject: Security Boundary

The `appproject.yaml` defines WHAT ArgoCD is allowed to do:

```
AppProject "devsecops-platform"
  |
  |-- Allowed source repos: Only our GitHub repo
  |-- Allowed destinations: Only our cluster
  |-- Allowed cluster resources: Namespaces, NetworkPolicies, OPA constraints
  |-- RBAC:
       |-- platform-admin: Full access to everything
       |-- developer: Can view all, sync dev/staging only (NOT prod)
       +-- security-viewer: Read-only access for auditing
```

### Sync Policies by Environment

```
DEV:
  - Auto-sync: ON (deploy automatically when Git changes)
  - Prune: OFF (don't delete things automatically — safer for dev)
  - Self-heal: OFF (allow manual kubectl changes for debugging)

STAGING:
  - Auto-sync: ON
  - Prune: ON (clean up removed resources)
  - Self-heal: OFF (allow temporary manual changes)

PROD:
  - Auto-sync: ON
  - Prune: ON
  - Self-heal: ON (revert ANY manual kubectl changes — Git is truth)
```

---

## 7. Layer 4: Helm Values (ArgoCD's Own Config)

### What are Helm Values?

ArgoCD itself is installed via **Helm** (a Kubernetes package manager). Helm charts accept "values" files that customize the installation. We have different values per environment to control ArgoCD's own behavior.

### Our Helm Values Structure

```
kubernetes/argocd/
|-- argocd-values.yaml                 ← BASE: Production-grade ArgoCD config
+-- helm-values/
    |-- values-dev.yaml                ← Dev: 1 replica, relaxed settings
    |-- values-staging.yaml            ← Staging: Moderate settings
    +-- values-prod.yaml               ← Prod: HA, strict settings
```

### How Values Overlay Works

Helm merges values files in order. Later files override earlier ones:

```bash
# When deploying ArgoCD to dev:
helm install argocd argo/argo-cd \
  -f argocd-values.yaml \        # Base (loaded first)
  -f helm-values/values-dev.yaml  # Dev overrides (loaded second, wins on conflicts)
```

**Base** says: `replicaCount: 3` (HA for production)
**Dev override** says: `replicaCount: 1` (save money in dev)
**Result**: Dev gets `replicaCount: 1`

### Key Differences

| ArgoCD Setting | Dev | Staging | Prod |
|---------------|-----|---------|------|
| Replicas | 1 | 1 | 3 (HA) |
| Autoscaling | Off | On (1-3) | On (3-10) |
| Notifications | Failures only | All events | All + PagerDuty |
| Domain | dev.argocd.internal | staging.argocd.internal | argocd.internal |

---

## 8. Layer 5: CI/CD Pipeline (GitHub Actions)

### Pipeline Overview

The CI/CD pipeline in `ci-cd/github-actions/ci-pipeline.yml` automates everything:

```
git push → Lint → Security Scan → Build → Deploy
                                            |
                                   Which branch did you push to?
                                   |          |          |
                                develop    staging     main
                                   |          |          |
                                  DEV      STAGING     PROD
```

### The Matrix Strategy

Instead of writing 3 separate deploy jobs, we use a **matrix**:

```yaml
# One job definition, runs 3 times with different values
deploy:
  strategy:
    matrix:
      include:
        - environment: dev
          branch: refs/heads/develop
          cluster_name: devsecops-dev-cluster

        - environment: staging
          branch: refs/heads/staging
          cluster_name: devsecops-staging-cluster

        - environment: prod
          branch: refs/heads/main
          cluster_name: devsecops-prod-cluster
```

GitHub Actions creates 3 parallel jobs from this matrix. Each job checks if the current Git branch matches its `branch` value. If not, it skips itself.

### Pipeline Stages in Detail

```
Stage 1: LINT
  What: Checks code quality and formatting
  Tools: terraform fmt, kube-linter, yamllint, shellcheck
  Runs on: Every push and PR
  If fails: Nothing else runs (saves time)

Stage 2: SECURITY SCAN
  What: Finds vulnerabilities and misconfigurations
  Tools: tfsec, Checkov, Trivy, Kubescape, Gitleaks
  Runs on: After lint passes
  If fails: Blocks deployment

Stage 3: BUILD
  What: Builds Docker image, pushes to ECR
  Tools: Docker Buildx, Trivy image scanner
  Runs on: Push events only (not PRs)
  Output: Image tag for deployment

Stage 4: TERRAFORM PLAN (PRs only)
  What: Shows infrastructure changes for ALL environments
  Uses: Matrix strategy to plan dev + staging + prod in parallel
  Output: PR comments showing plan for each environment

Stage 5: DEPLOY (Push to branch)
  What: Applies infrastructure + syncs ArgoCD
  Uses: Matrix strategy with branch-matching
  Steps: terragrunt apply → argocd sync → smoke test → notify
```

---

## 9. Complete Flow Walkthrough

Let's follow a real change through the entire system:

### Scenario: You want to change an OPA policy to also require a "cost-center" label

#### Step 1: Make the change in the base

Edit `kubernetes/base/security-policies/opa-constraints.yaml`:
```yaml
parameters:
  labels:
    - "app.kubernetes.io/name"
    - "app.kubernetes.io/managed-by"
    - "environment"
    - "cost-center"        # ← NEW: Added this label requirement
```

#### Step 2: Push to develop branch

```bash
git checkout develop
git add kubernetes/base/security-policies/opa-constraints.yaml
git commit -m "Add cost-center label requirement to OPA policy"
git push origin develop
```

#### Step 3: What happens automatically

```
1. GitHub Actions triggers (push to develop)
   |
   v
2. LINT stage runs → checks YAML syntax ✓
   |
   v
3. SECURITY SCAN stage runs → scans for issues ✓
   |
   v
4. BUILD stage runs → builds container image ✓
   |
   v
5. DEPLOY matrix runs:
   - deploy-dev:     branch-check → MATCH (develop == develop) → RUNS
   - deploy-staging: branch-check → SKIP
   - deploy-prod:    branch-check → SKIP
   |
   v
6. Dev deployment:
   a. terragrunt apply → No infra changes (we changed K8s manifests, not infra)
   b. argocd app sync security-policies-dev
      |
      | ArgoCD detects the change in develop branch
      v
   c. ArgoCD runs: kustomize build kubernetes/overlays/dev/
      |
      | Dev overlay changes enforcementAction to "warn"
      v
   d. ArgoCD applies the updated OPA constraint to the dev cluster
      |
      | The new cost-center label requirement is now active in dev
      | but with enforcementAction: warn (won't block anything)
      v
   e. Smoke tests run → pass ✓
   f. Slack notification: "Dev deployment succeeded"
```

#### Step 4: Test in dev, then promote to staging

```bash
# Verify in dev
kubectl get constraints require-mandatory-labels -o yaml
# Confirm the cost-center label is in the parameters list
# Confirm enforcementAction: warn (dev overlay)

# Promote to staging
git checkout staging
git merge develop
git push origin staging
# Same pipeline runs, but this time deploy-staging matches
# Staging gets enforcementAction: deny for labels (stricter!)
```

#### Step 5: Promote to production

```bash
# Create a PR from staging to main
git checkout main
git merge staging
git push origin main
# Pipeline runs, deploy-prod matches
# Prod gets the strictest enforcement (base settings, no patches)
```

#### What happened at each environment:

```
DEV:     cost-center label required, enforcementAction: WARN
         (deployments without cost-center label show a warning)

STAGING: cost-center label required, enforcementAction: DENY
         (deployments without cost-center label are BLOCKED)

PROD:    cost-center label required, enforcementAction: DENY
         (same as staging — maximum enforcement)
```

---

## 10. File-by-File Reference

### Terragrunt Files

| File | Purpose | Called By |
|------|---------|-----------|
| `terraform/terragrunt.hcl` | Root config: S3 backend, provider versions, shared settings | All environment terragrunt.hcl files (via `include "root"`) |
| `terraform/environments/dev/env.hcl` | Dev variables: environment name, region, account ID | Root terragrunt.hcl (via `read_terragrunt_config`) |
| `terraform/environments/dev/terragrunt.hcl` | Dev entry point: inherits root, sets dev inputs | You (via `terragrunt plan/apply`) or CI/CD pipeline |
| `terraform/environments/staging/env.hcl` | Staging variables | Root terragrunt.hcl |
| `terraform/environments/staging/terragrunt.hcl` | Staging entry point | You or CI/CD pipeline |
| `terraform/environments/prod/env.hcl` | Prod variables | Root terragrunt.hcl |
| `terraform/environments/prod/terragrunt.hcl` | Prod entry point | You or CI/CD pipeline |
| `terraform/environments/prod/main.tf` | The actual Terraform code (modules, variables, outputs) | ALL environments (dev and staging `source` point here) |
| `terraform/_envcommon/networking.hcl` | Shared config for calling the networking module | Used as reference for _envcommon pattern |
| `terraform/_envcommon/eks-cluster.hcl` | Shared config for calling the EKS module | Used as reference for _envcommon pattern |
| `terraform/_envcommon/monitoring.hcl` | Shared config for calling the monitoring module | Used as reference for _envcommon pattern |
| `terraform/_envcommon/security-tools.hcl` | Shared config for calling the security-tools module | Used as reference for _envcommon pattern |

### Terraform Modules (Unchanged)

| File | Purpose |
|------|---------|
| `terraform/modules/networking/main.tf` | Creates VPC, subnets (public/private), NAT Gateway, flow logs |
| `terraform/modules/eks-cluster/main.tf` | Creates EKS cluster, node groups, KMS encryption, OIDC/IRSA |
| `terraform/modules/monitoring/main.tf` | Installs Prometheus, Grafana, Alertmanager via Helm |
| `terraform/modules/security-tools/main.tf` | Installs Falco, Trivy Operator, OPA Gatekeeper via Helm |

### Kustomize Files

| File | Purpose | Called By |
|------|---------|-----------|
| `kubernetes/base/security-policies/kustomization.yaml` | Lists base security policy resources | Overlay kustomization.yaml files |
| `kubernetes/base/security-policies/pod-security.yaml` | Namespace PSS labels, ResourceQuota, LimitRange, RBAC | Kustomize base |
| `kubernetes/base/security-policies/network-policies.yaml` | Zero-trust NetworkPolicies (deny-all + specific allows) | Kustomize base |
| `kubernetes/base/security-policies/opa-constraints.yaml` | OPA ConstraintTemplates + Constraints | Kustomize base |
| `kubernetes/base/monitoring/kustomization.yaml` | Lists base monitoring resources | Overlay kustomization.yaml files |
| `kubernetes/base/monitoring/prometheus-rules.yaml` | PrometheusRule with 17 alert rules | Kustomize base |
| `kubernetes/overlays/dev/kustomization.yaml` | Dev overlay: all OPA → warn, relaxed PSS | ArgoCD (via ApplicationSet) |
| `kubernetes/overlays/dev/patch-prometheus-rules.yaml` | Dev alert patches: high thresholds, long delays | Dev kustomization.yaml |
| `kubernetes/overlays/staging/kustomization.yaml` | Staging overlay: mixed OPA enforcement | ArgoCD (via ApplicationSet) |
| `kubernetes/overlays/staging/patch-prometheus-rules.yaml` | Staging alert patches: moderate thresholds | Staging kustomization.yaml |
| `kubernetes/overlays/prod/kustomization.yaml` | Prod overlay: uses base as-is (strictest) | ArgoCD (via ApplicationSet) |

### ArgoCD Files

| File | Purpose | Called By |
|------|---------|-----------|
| `kubernetes/argocd/appproject.yaml` | Defines project security boundary and RBAC | ArgoCD (applied to cluster) |
| `kubernetes/argocd/applicationsets.yaml` | Templates that generate per-env Applications | ArgoCD ApplicationSet Controller |
| `kubernetes/argocd/argocd-values.yaml` | Base Helm values for ArgoCD installation | Helm (during ArgoCD install) |
| `kubernetes/argocd/helm-values/values-dev.yaml` | Dev ArgoCD overrides (1 replica, no autoscale) | Helm (merged with base values) |
| `kubernetes/argocd/helm-values/values-staging.yaml` | Staging ArgoCD overrides | Helm |
| `kubernetes/argocd/helm-values/values-prod.yaml` | Prod ArgoCD overrides (HA, full monitoring) | Helm |

### CI/CD and Scripts

| File | Purpose |
|------|---------|
| `ci-cd/github-actions/ci-pipeline.yml` | Multi-env CI/CD pipeline with matrix strategy |
| `scripts/security-audit.sh` | Manual security audit bash script |
| `scripts/incident-response.py` | Automated incident response Python script |

---

## 11. Common Operations Runbook

### Adding a New Environment (e.g., "qa")

1. **Create Terragrunt files:**
```bash
mkdir -p terraform/environments/qa
```

Create `terraform/environments/qa/env.hcl`:
```hcl
locals {
  environment = "qa"
  aws_region  = "us-east-1"
  account_id  = "123456789012"
}
```

Create `terraform/environments/qa/terragrunt.hcl`:
```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${dirname(find_in_parent_folders())}//environments/prod"
}

inputs = {
  aws_region          = "us-east-1"
  vpc_cidr            = "10.30.0.0/16"    # Unique CIDR!
  kubernetes_version  = "1.29"
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 4
}
```

2. **Create Kustomize overlay:**
```bash
mkdir -p kubernetes/overlays/qa
```

Create `kubernetes/overlays/qa/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base/security-policies
  - ../../base/monitoring
commonLabels:
  environment: qa
# Add patches as needed (copy from staging as a starting point)
```

3. **Add to ApplicationSet:**

Edit `kubernetes/argocd/applicationsets.yaml` — add a new element to each generator's list:
```yaml
- environment: qa
  targetRevision: qa       # New 'qa' branch
  clusterUrl: https://kubernetes.default.svc
  overlayPath: kubernetes/overlays/qa
  prune: "true"
  selfHeal: "false"
```

4. **Add to CI/CD pipeline:**

Edit `ci-cd/github-actions/ci-pipeline.yml`:
- Add `qa` to the `on.push.branches` list
- Add a new matrix entry in the deploy job

5. **Deploy:**
```bash
cd terraform/environments/qa
terragrunt plan
terragrunt apply
```

### Changing an OPA Policy for One Environment

To change a policy in staging only, edit the staging overlay:

```bash
# Edit: kubernetes/overlays/staging/kustomization.yaml
# Add a new patch entry under "patches:"
```

### Promoting Changes Between Environments

```bash
# Feature branch → dev
git checkout develop
git merge feature/my-feature
git push origin develop

# dev → staging (after testing in dev)
git checkout staging
git merge develop
git push origin staging

# staging → prod (after testing in staging)
git checkout main
git merge staging
git push origin main
```

### Rolling Back a Deployment

```bash
# Option 1: Git revert (safest — creates a new commit that undoes changes)
git revert HEAD
git push origin main

# Option 2: ArgoCD rollback (quick — reverts to previous sync)
argocd app rollback security-policies-prod

# Option 3: Terraform rollback
cd terraform/environments/prod
git checkout HEAD~1 -- .   # Get previous version of files
terragrunt apply            # Apply previous infrastructure state
```

---

## 12. Troubleshooting

### Terragrunt Issues

**Error: "Could not find env.hcl"**
```
Cause: You're running terragrunt from the wrong directory
Fix: cd into an environment directory (e.g., terraform/environments/dev/)
```

**Error: "S3 bucket does not exist"**
```
Cause: First-time setup — Terragrunt auto-creates the bucket, but needs permissions
Fix: Ensure your AWS credentials have S3 and DynamoDB permissions
```

**Error: "State lock held by another process"**
```
Cause: A previous terragrunt run crashed without releasing the lock
Fix: terragrunt force-unlock <LOCK_ID>
Warning: Only do this if you're SURE no other process is running!
```

### Kustomize Issues

**Error: "resource not found in base"**
```
Cause: A patch targets a resource that doesn't exist in the base
Fix: Check that the target kind/name in your patch matches the base exactly
Debug: kubectl kustomize kubernetes/overlays/dev/ 2>&1 | head -20
```

**Error: "conflicting patches"**
```
Cause: Two patches modify the same field
Fix: Combine them into one patch or check for duplicates
```

### ArgoCD Issues

**Application stuck in "OutOfSync"**
```
Cause: ArgoCD detects differences between Git and cluster
Debug: argocd app diff security-policies-dev
Fix: argocd app sync security-policies-dev
```

**Application shows "Degraded" health**
```
Cause: Deployed resources have errors (CrashLoopBackOff, etc.)
Debug: argocd app get security-policies-dev
       kubectl get events -n dev --sort-by=.lastTimestamp
```

**ApplicationSet not generating Applications**
```
Cause: Usually a YAML syntax error in applicationsets.yaml
Debug: kubectl logs -n argocd deployment/argocd-applicationset-controller
```

### CI/CD Pipeline Issues

**Deploy job runs but skips all steps**
```
Cause: Branch doesn't match any matrix entry
Fix: Check that you pushed to the right branch (develop, staging, or main)
Debug: Look at the "Check branch match" step output
```

**Terraform plan shows unexpected changes**
```
Cause: State drift — someone made manual changes outside Terraform
Debug: terragrunt plan  # Read the plan output carefully
Fix: Either import the manual changes or revert them
```

---

## Quick Reference Card

```
DEPLOYING INFRASTRUCTURE:
  cd terraform/environments/<env>
  terragrunt plan       # Preview
  terragrunt apply      # Deploy

PREVIEWING KUSTOMIZE OUTPUT:
  kubectl kustomize kubernetes/overlays/<env>/

CHECKING ARGOCD STATUS:
  argocd app list
  argocd app get security-policies-<env>
  argocd app sync security-policies-<env>

PROMOTING CHANGES:
  develop → staging → main
  (merge branch, push, CI/CD handles the rest)

ADDING A NEW ENVIRONMENT:
  1. terraform/environments/<env>/env.hcl + terragrunt.hcl
  2. kubernetes/overlays/<env>/kustomization.yaml
  3. Add to applicationsets.yaml generators list
  4. Add to ci-pipeline.yml matrix

KEY FILES:
  Infrastructure values: terraform/environments/<env>/terragrunt.hcl
  K8s policy overrides:  kubernetes/overlays/<env>/kustomization.yaml
  ArgoCD app generator:  kubernetes/argocd/applicationsets.yaml
  CI/CD pipeline:        ci-cd/github-actions/ci-pipeline.yml
```
