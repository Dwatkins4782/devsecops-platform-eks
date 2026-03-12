# Hands-On Setup Guide: Deploy the DevSecOps Platform From Scratch

> **What is this?** A step-by-step lab walkthrough to deploy the entire DevSecOps platform
> on your own AWS account. By the end, you'll have 3 fully working Kubernetes clusters
> (dev/staging/prod) with security tools, monitoring, GitOps, and CI/CD.
>
> **Time required:** ~2-3 hours for dev environment, ~1 hour each for staging/prod
>
> **Cost warning:** Running all 3 environments costs approximately **$15-25/day**.
> See [Appendix A: Cost Estimates](#appendix-a-cost-estimates) for details and how to minimize costs.
>
> **Prerequisites knowledge:** Basic terminal/command line usage. No prior Kubernetes,
> Terraform, or AWS experience required — everything is explained step by step.

---

## Table of Contents

- [Phase 0: Install Required Tools](#phase-0-install-required-tools)
- [Phase 1: AWS Account Setup](#phase-1-aws-account-setup)
- [Phase 2: GitHub Repository Setup](#phase-2-github-repository-setup)
- [Phase 3: Create Terraform State Backend](#phase-3-create-terraform-state-backend)
- [Phase 4: Deploy Dev Environment](#phase-4-deploy-dev-environment)
- [Phase 5: Verify Security Tools](#phase-5-verify-security-tools)
- [Phase 6: Verify Monitoring Stack](#phase-6-verify-monitoring-stack)
- [Phase 7: Install and Configure ArgoCD](#phase-7-install-and-configure-argocd)
- [Phase 8: Deploy Staging Environment](#phase-8-deploy-staging-environment)
- [Phase 9: Deploy Production Environment](#phase-9-deploy-production-environment)
- [Phase 10: Test the CI/CD Pipeline End-to-End](#phase-10-test-the-cicd-pipeline-end-to-end)
- [Appendix A: Cost Estimates](#appendix-a-cost-estimates)
- [Appendix B: Complete Teardown](#appendix-b-complete-teardown)
- [Appendix C: Common Errors and Fixes](#appendix-c-common-errors-and-fixes)

---

## Phase 0: Install Required Tools

Before you begin, you need these CLI tools installed on your machine.

### Tool Checklist

| Tool | Minimum Version | What It Does |
|------|----------------|--------------|
| AWS CLI | v2.x | Authenticates you to AWS and manages resources |
| Terraform | >= 1.6.0 | Creates cloud infrastructure from code |
| Terragrunt | >= 0.54.12 | Wraps Terraform for multi-environment DRY configs |
| kubectl | >= 1.29 | Manages Kubernetes clusters |
| Helm | >= 3.14 | Installs packages (charts) on Kubernetes |
| ArgoCD CLI | >= 2.10 | Manages GitOps deployments (optional but recommended) |
| Docker | Latest | Builds container images |
| git | Latest | Version control |

### macOS Installation

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install all tools
brew install awscli
brew install terraform
brew install terragrunt
brew install kubectl
brew install helm
brew install argocd
brew install --cask docker    # Docker Desktop
brew install git
```

### Windows Installation

```powershell
# Install Chocolatey if you don't have it (run PowerShell as Admin)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install all tools
choco install awscli -y
choco install terraform -y
choco install terragrunt -y
choco install kubernetes-cli -y
choco install kubernetes-helm -y
choco install argocd-cli -y
choco install docker-desktop -y
choco install git -y
```

### Linux (Ubuntu/Debian) Installation

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Terraform
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform

# Terragrunt
TERRAGRUNT_VERSION="0.54.12"
wget "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64"
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

# kubectl
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ArgoCD CLI
curl -sSL -o argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd-linux-amd64 && sudo mv argocd-linux-amd64 /usr/local/bin/argocd

# Docker
sudo apt-get install docker.io -y
sudo usermod -aG docker $USER
```

### Verify All Tools Are Installed

Run each command — if you get a version number, it's working:

```bash
aws --version          # Should show: aws-cli/2.x.x ...
terraform --version    # Should show: Terraform v1.6.x+
terragrunt --version   # Should show: terragrunt version v0.54.x+
kubectl version --client # Should show: Client Version: v1.29.x+
helm version           # Should show: version.BuildInfo{Version:"v3.14.x+"}
argocd version --client  # Should show: argocd: v2.10.x+
docker --version       # Should show: Docker version 2x.x.x
git --version          # Should show: git version 2.x.x
```

> **Checkpoint:** All 8 tools showing version numbers? Great, move to Phase 1!

---

## Phase 1: AWS Account Setup

### Step 1.1: Create an AWS Account (Skip if You Already Have One)

1. Go to https://aws.amazon.com/ and click "Create an AWS Account"
2. Follow the signup wizard (you'll need a credit card)
3. Select the **Free Tier** where possible

> **Cost warning:** This lab will create resources that cost money (~$5-8/day for dev only).
> Always run the [teardown steps](#appendix-b-complete-teardown) when you're done practicing.

### Step 1.2: Create an IAM User for CLI Access

You need a user with programmatic access. Do NOT use your root account.

1. Go to **AWS Console** → **IAM** → **Users** → **Create User**
2. Username: `devsecops-admin`
3. Select **Attach policies directly**
4. Attach these AWS managed policies:
   - `AmazonEKSClusterPolicy`
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonVPCFullAccess`
   - `AmazonEC2FullAccess`
   - `AmazonS3FullAccess`
   - `AmazonDynamoDBFullAccess`
   - `IAMFullAccess`
   - `CloudWatchFullAccess`
   - `AWSKeyManagementServicePowerUser`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEKSServicePolicy`

> **Why so many policies?** This platform creates VPCs, EKS clusters, KMS keys,
> CloudWatch logs, S3 buckets, DynamoDB tables, IAM roles, and more. Each service
> needs its own permission. In production, you'd use a custom least-privilege policy.

5. Click **Next** → **Create User**
6. Click on the user → **Security credentials** → **Create access key**
7. Select **Command Line Interface (CLI)** → **Next** → **Create access key**
8. **SAVE** the Access Key ID and Secret Access Key — you'll need them next

### Step 1.3: Configure AWS CLI

```bash
aws configure
```

When prompted, enter:
```
AWS Access Key ID:     <paste your Access Key ID>
AWS Secret Access Key: <paste your Secret Access Key>
Default region name:   us-east-1
Default output format: json
```

### Step 1.4: Verify AWS Access

```bash
aws sts get-caller-identity
```

You should see something like:
```json
{
    "UserId": "AIDAIOSFODNN7EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/devsecops-admin"
}
```

> **Write down your Account ID** (the 12-digit number). You'll need it in several places.

> **Checkpoint:** `aws sts get-caller-identity` shows your account? Move to Phase 2!

---

## Phase 2: GitHub Repository Setup

### Step 2.1: Fork the Repository

1. Go to https://github.com/Dwatkins4782/devsecops-platform-eks
2. Click **Fork** (top right)
3. Select your GitHub account as the destination
4. Clone YOUR fork to your local machine:

```bash
git clone https://github.com/YOUR_USERNAME/devsecops-platform-eks.git
cd devsecops-platform-eks
```

### Step 2.2: Create Environment Branches

The CI/CD pipeline deploys based on which branch you push to. You need 3 branches:

```bash
# You're on 'master' (or 'main') — this is your production branch
# Create the develop and staging branches

git checkout -b develop
git push origin develop

git checkout -b staging
git push origin staging

# Go back to the main branch
git checkout master
```

Now you have:
- `master` (or `main`) → Production deployments
- `staging` → Staging deployments
- `develop` → Dev deployments

### Step 2.3: Update Account ID in Configuration Files

Replace the placeholder account ID with YOUR AWS account ID:

```bash
# Replace 123456789012 with your actual account ID in all env.hcl files
# On macOS/Linux:
sed -i 's/123456789012/YOUR_ACCOUNT_ID/g' terraform/environments/dev/env.hcl
sed -i 's/123456789012/YOUR_ACCOUNT_ID/g' terraform/environments/staging/env.hcl
sed -i 's/123456789012/YOUR_ACCOUNT_ID/g' terraform/environments/prod/env.hcl

# Also update the ECR registry in the allowed registries OPA constraint
sed -i 's/123456789012/YOUR_ACCOUNT_ID/g' kubernetes/base/security-policies/opa-constraints.yaml
```

> **Windows users:** Open each file in a text editor and find-replace `123456789012` with your account ID.

### Step 2.4: Set Up GitHub Actions Secrets (For CI/CD — Optional for Now)

> **Note:** You can skip this step and come back to it in Phase 10 when you test the CI/CD pipeline.

1. Go to your fork on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add each:

| Secret Name | Value | Where to Get It |
|------------|-------|-----------------|
| `AWS_ACCOUNT_ID` | Your 12-digit account ID | `aws sts get-caller-identity` |
| `AWS_OIDC_ROLE_ARN` | `arn:aws:iam::YOUR_ACCOUNT_ID:role/github-actions-role` | Created in Step 2.5 |
| `GRAFANA_ADMIN_PASSWORD` | Any strong password (e.g., `DevSecOps2024!`) | You choose |
| `SLACK_WEBHOOK_URL` | A Slack webhook URL (or empty string `""` for now) | [Create one](https://api.slack.com/messaging/webhooks) |
| `SLACK_DEPLOYMENT_WEBHOOK` | Same as above (or `""`) | Same |
| `ARGOCD_AUTH_TOKEN` | Generated after ArgoCD install (Phase 7) | Phase 7 |

### Step 2.5: Create GitHub OIDC Provider in AWS (For CI/CD — Optional for Now)

> **What is this?** Instead of storing AWS access keys in GitHub (insecure), GitHub
> Actions uses OpenID Connect (OIDC) to assume an IAM role. This is the secure way.

```bash
# Create the OIDC provider (one-time setup)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Now create the IAM role that GitHub Actions will assume. Create a file called `github-oidc-role.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/devsecops-platform-eks:*"
        }
      }
    }
  ]
}
```

> **Important:** Replace `YOUR_ACCOUNT_ID` and `YOUR_GITHUB_USERNAME` in the file above.

```bash
# Create the role
aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file://github-oidc-role.json

# Attach the same policies as your IAM user
aws iam attach-role-policy --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-role-policy --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
aws iam attach-role-policy --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-role-policy --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-role-policy --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
aws iam attach-role-policy --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
aws iam attach-role-policy --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser

# Clean up the temp file
rm github-oidc-role.json
```

> **Checkpoint:** Your fork is cloned, branches are created, and account IDs are updated? Move to Phase 3!

---

## Phase 3: Create Terraform State Backend

Terraform needs a place to store its "state" — a record of what infrastructure it has created. We use S3 buckets (one per environment) with DynamoDB for locking.

### Step 3.1: Create S3 Buckets for State

```bash
# Create a bucket for each environment
# Note: Bucket names must be globally unique. If these are taken, add a random suffix.

aws s3 mb s3://devsecops-tfstate-dev --region us-east-1
aws s3 mb s3://devsecops-tfstate-staging --region us-east-1
aws s3 mb s3://devsecops-tfstate-prod --region us-east-1

# Enable versioning (protects against accidental state file deletion)
aws s3api put-bucket-versioning --bucket devsecops-tfstate-dev \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket devsecops-tfstate-staging \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-versioning --bucket devsecops-tfstate-prod \
  --versioning-configuration Status=Enabled

# Enable encryption at rest
aws s3api put-bucket-encryption --bucket devsecops-tfstate-dev \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-encryption --bucket devsecops-tfstate-staging \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-encryption --bucket devsecops-tfstate-prod \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block all public access
for env in dev staging prod; do
  aws s3api put-public-access-block --bucket "devsecops-tfstate-${env}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
done
```

> **If the bucket names are taken** (they must be globally unique), modify the bucket
> names in the root `terraform/terragrunt.hcl` file. Find the `remote_state` block
> and change the `bucket` line from `"devsecops-tfstate-${local.environment}"` to
> your custom naming pattern.

### Step 3.2: Create DynamoDB Table for State Locking

```bash
aws dynamodb create-table \
  --table-name devsecops-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

> **What does this do?** When someone runs `terragrunt apply`, it writes a "lock" to this
> table. If someone else tries to run `apply` at the same time, they'll see "state is locked"
> and have to wait. This prevents two people from changing infrastructure simultaneously.

### Step 3.3: Verify Backend is Ready

```bash
# Check the buckets exist
aws s3 ls | grep devsecops-tfstate

# Check the DynamoDB table exists
aws dynamodb describe-table --table-name devsecops-terraform-locks \
  --query 'Table.TableStatus'
```

You should see `"ACTIVE"` for the table status.

> **Checkpoint:** 3 S3 buckets and 1 DynamoDB table created? Move to Phase 4!

---

## Phase 4: Deploy Dev Environment

This is the exciting part — we're creating real AWS infrastructure! Start with dev because it's the cheapest and fastest.

### Step 4.1: Initialize and Preview Changes

```bash
cd terraform/environments/dev
terragrunt init
```

> **What just happened?**
> - Terragrunt read `dev/terragrunt.hcl` and its parent `terraform/terragrunt.hcl`
> - It configured the S3 backend (creating the state file path)
> - It generated `backend.tf` and `versions_override.tf`
> - It downloaded all required Terraform providers (AWS, Helm, Kubernetes, TLS)

Now preview what will be created:

```bash
terragrunt plan
```

> **What you'll see:** A large output showing ~40-60 resources to create:
> VPC, subnets, NAT gateways, EKS cluster, node group, security groups,
> IAM roles, KMS keys, Prometheus, Grafana, Falco, Trivy, OPA Gatekeeper, etc.
>
> Look for the summary line at the bottom:
> `Plan: XX to add, 0 to change, 0 to destroy.`

### Step 4.2: Deploy!

```bash
terragrunt apply
```

When prompted, type `yes` and press Enter.

> **How long does this take?** About **15-20 minutes**. The EKS cluster creation
> alone takes ~10 minutes. The Helm chart installations (Prometheus, Falco, etc.)
> take another 5-10 minutes.
>
> **Don't close your terminal!** If the process is interrupted, run `terragrunt apply`
> again — Terraform will pick up where it left off.

When complete, you'll see:
```
Apply complete! Resources: XX added, 0 changed, 0 destroyed.

Outputs:
  cluster_endpoint = "https://XXXXX.gr7.us-east-1.eks.amazonaws.com"
  cluster_name = "devsecops-dev-cluster"
  ...
```

### Step 4.3: Connect kubectl to Your New Cluster

```bash
aws eks update-kubeconfig \
  --name devsecops-dev-cluster \
  --region us-east-1
```

This adds the cluster to your `~/.kube/config` file so `kubectl` can talk to it.

### Step 4.4: Verify the Cluster is Running

```bash
# Check nodes are ready
kubectl get nodes
```

Expected output (1 node for dev):
```
NAME                             STATUS   ROLES    AGE   VERSION
ip-10-10-xxx-xxx.ec2.internal    Ready    <none>   5m    v1.29.x
```

```bash
# Check all pods are running
kubectl get pods -A
```

You should see pods in these namespaces:
- `kube-system` — Core Kubernetes components (CoreDNS, kube-proxy, VPC CNI)
- `monitoring` — Prometheus, Grafana, Alertmanager
- `security-tools` — Falco, Trivy Operator, OPA Gatekeeper
- `calico-system` — Calico network policy engine

```bash
# Check all namespaces
kubectl get namespaces
```

> **Checkpoint:** `kubectl get nodes` shows 1 Ready node? Congratulations, your dev cluster is live! Move to Phase 5!

---

## Phase 5: Verify Security Tools

Let's make sure all the security tools are working.

### Step 5.1: Check Falco (Runtime Security)

```bash
# Check Falco pods are running
kubectl get pods -n security-tools -l app.kubernetes.io/name=falco

# Check Falco logs (you should see "Falco initialized" messages)
kubectl logs -n security-tools -l app.kubernetes.io/name=falco --tail=20
```

### Step 5.2: Check Trivy Operator (Vulnerability Scanner)

```bash
# Check Trivy pods
kubectl get pods -n security-tools -l app.kubernetes.io/name=trivy-operator

# After a few minutes, Trivy will have scanned running images
# Check for vulnerability reports
kubectl get vulnerabilityreports -A
```

> **Note:** It may take 5-10 minutes for Trivy to complete its first scan.

### Step 5.3: Check OPA Gatekeeper (Policy Engine)

```bash
# Check Gatekeeper pods
kubectl get pods -n gatekeeper-system

# Check constraint templates are installed
kubectl get constrainttemplates

# Check constraints are active
kubectl get constraints
```

Expected constraint templates:
```
NAME                         AGE
k8srequiredlabels           5m
k8sblocklatestimages        5m
k8srequireresourcelimits    5m
```

### Step 5.4: Test an OPA Policy Violation

Let's test that OPA Gatekeeper is working by trying to deploy something it should block.
Remember, in dev, policies are set to "warn" mode (not "deny"), so it will show a warning
but still allow the deployment:

```bash
# Try deploying a pod using the :latest tag (OPA should warn about this)
kubectl run test-latest --image=nginx:latest -n default

# Check for warning events
kubectl get events -n default --sort-by=.lastTimestamp | head -10

# Clean up the test pod
kubectl delete pod test-latest -n default
```

### Step 5.5: Run the Security Audit Script

```bash
# Make the script executable
chmod +x scripts/security-audit.sh

# Run the security audit
./scripts/security-audit.sh
```

This script checks:
- Pod security configurations
- RBAC bindings and permissions
- Network policies
- Secret management practices
- Image scanning compliance

> **Checkpoint:** Falco, Trivy, and Gatekeeper pods all running? OPA constraints active? Move to Phase 6!

---

## Phase 6: Verify Monitoring Stack

### Step 6.1: Access Prometheus

```bash
# Port-forward Prometheus to your local machine
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Open your browser to **http://localhost:9090**

Try some queries:
- `up` — Shows all monitored targets and their status
- `kube_pod_info` — Shows information about all pods
- `node_cpu_seconds_total` — Shows CPU usage data

Press `Ctrl+C` to stop port-forwarding.

### Step 6.2: Access Grafana

```bash
# Get the Grafana admin password
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 --decode; echo

# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open your browser to **http://localhost:3000**

- Username: `admin`
- Password: (the password printed above, or the one you set in your terragrunt inputs)

Navigate to **Dashboards** — you should see pre-built dashboards for:
- Kubernetes cluster overview
- Node metrics
- Pod metrics

Press `Ctrl+C` to stop port-forwarding.

### Step 6.3: Check Alertmanager

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Open **http://localhost:9093** to see the Alertmanager UI.

Press `Ctrl+C` to stop port-forwarding.

### Step 6.4: Preview Kustomize Output

Let's see what Kustomize would produce for dev:

```bash
kubectl kustomize kubernetes/overlays/dev/
```

This outputs the merged YAML — base manifests with dev patches applied.
Notice the `enforcementAction: warn` on all OPA constraints (dev is relaxed).

> **Checkpoint:** Prometheus, Grafana, and Alertmanager all accessible? Move to Phase 7!

---

## Phase 7: Install and Configure ArgoCD

ArgoCD watches your Git repository and automatically deploys changes to the cluster.

### Step 7.1: Install ArgoCD via Helm

```bash
# Add the ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD with your dev values overlay
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f kubernetes/argocd/argocd-values.yaml \
  -f kubernetes/argocd/helm-values/values-dev.yaml \
  --wait \
  --timeout 5m
```

> **What did this do?**
> - Created the `argocd` namespace
> - Installed ArgoCD server, controller, repo-server, and Redis
> - Applied your base config (`argocd-values.yaml`)
> - Overlaid dev-specific settings (1 replica, no autoscaling)

### Step 7.2: Get the Admin Password

```bash
# ArgoCD generates a random admin password on first install
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode; echo
```

> **Save this password!** You'll need it to log into the ArgoCD UI.

### Step 7.3: Access the ArgoCD UI

```bash
# Port-forward ArgoCD server
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Open your browser to **https://localhost:8080**

> **Your browser will show a security warning** (self-signed certificate).
> Click "Advanced" → "Proceed to localhost" (this is safe for local access).

Login:
- Username: `admin`
- Password: (from Step 7.2)

You'll see an empty Applications screen — we'll populate it next.

### Step 7.4: Login with the ArgoCD CLI

Open a **new terminal window** (keep the port-forward running):

```bash
# Login to ArgoCD
argocd login localhost:8080 \
  --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode) \
  --insecure
```

### Step 7.5: Apply the AppProject and ApplicationSets

```bash
# Apply the project definition (security boundary)
kubectl apply -f kubernetes/argocd/appproject.yaml

# Apply the ApplicationSets (auto-generates per-environment Applications)
kubectl apply -f kubernetes/argocd/applicationsets.yaml
```

### Step 7.6: Verify Applications Were Created

```bash
# List all ArgoCD applications
argocd app list
```

You should see 6 applications auto-generated by the ApplicationSets:
```
NAME                           CLUSTER                         NAMESPACE    STATUS     HEALTH
security-policies-dev          https://kubernetes.default.svc   dev         Synced     Healthy
security-policies-staging      https://kubernetes.default.svc   staging     OutOfSync  Missing
security-policies-prod         https://kubernetes.default.svc   prod        OutOfSync  Missing
monitoring-configs-dev         https://kubernetes.default.svc   monitoring  Synced     Healthy
monitoring-configs-staging     https://kubernetes.default.svc   monitoring  OutOfSync  Missing
monitoring-configs-prod        https://kubernetes.default.svc   monitoring  OutOfSync  Missing
```

> **Note:** The staging and prod applications show "OutOfSync" because those branches
> don't exist yet (or don't have the overlay content). This is expected — they'll sync
> when you push to those branches.

Refresh the ArgoCD UI in your browser — you should see all 6 apps displayed!

### Step 7.7: Sync the Dev Applications

```bash
# Sync security policies for dev
argocd app sync security-policies-dev

# Sync monitoring configs for dev
argocd app sync monitoring-configs-dev
```

Watch in the ArgoCD UI as the applications deploy. Click on an app to see all the
individual Kubernetes resources it created.

> **Checkpoint:** ArgoCD installed, 6 applications visible, dev apps synced? Move to Phase 8!

---

## Phase 8: Deploy Staging Environment

Now let's deploy the staging environment to see how multi-environment works.

### Step 8.1: Deploy Staging Infrastructure

```bash
cd terraform/environments/staging
terragrunt init
terragrunt plan
```

Compare the plan output to dev — notice the differences:
- `node_instance_types` = `["t3.large"]` (bigger than dev's t3.medium)
- `node_desired_size` = 2 (more nodes than dev's 1)
- `vpc_cidr` = `"10.20.0.0/16"` (different network range)

```bash
terragrunt apply
# Type 'yes' when prompted
# Wait ~15-20 minutes
```

### Step 8.2: Connect to Staging Cluster

```bash
aws eks update-kubeconfig \
  --name devsecops-staging-cluster \
  --region us-east-1

# Verify (should show 2 nodes)
kubectl get nodes
```

> **Switching between clusters:** You now have TWO clusters in your kubeconfig.
> To switch between them:
> ```bash
> # List available contexts
> kubectl config get-contexts
>
> # Switch to dev
> kubectl config use-context arn:aws:eks:us-east-1:YOUR_ACCOUNT_ID:cluster/devsecops-dev-cluster
>
> # Switch to staging
> kubectl config use-context arn:aws:eks:us-east-1:YOUR_ACCOUNT_ID:cluster/devsecops-staging-cluster
> ```

### Step 8.3: Install ArgoCD on Staging

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f kubernetes/argocd/argocd-values.yaml \
  -f kubernetes/argocd/helm-values/values-staging.yaml \
  --wait \
  --timeout 5m
```

### Step 8.4: Compare Staging vs Dev Kustomize Output

```bash
# See what staging produces (from your repo root, not the terraform dir)
cd ~/devsecops-platform-eks  # or wherever you cloned the repo
kubectl kustomize kubernetes/overlays/staging/
```

Compare with dev:
```bash
diff <(kubectl kustomize kubernetes/overlays/dev/) \
     <(kubectl kustomize kubernetes/overlays/staging/)
```

Notice the differences:
- Staging has SOME constraints as `deny` and some as `warn` (mixed enforcement)
- Alert thresholds are moderate (between dev's relaxed and prod's strict)
- The `environment` label is `staging`

> **Checkpoint:** Staging cluster running with 2 nodes? Differences visible in Kustomize output? Move to Phase 9!

---

## Phase 9: Deploy Production Environment

### Step 9.1: Deploy Production Infrastructure

```bash
cd terraform/environments/prod
terragrunt init
terragrunt plan
```

Notice prod's plan shows:
- `node_instance_types` = `["t3.xlarge"]` (largest instances)
- `node_desired_size` = 3, `node_max_size` = 10 (auto-scaling up to 10)
- `vpc_cidr` = `"10.0.0.0/16"` (the primary network range)

```bash
terragrunt apply
# Type 'yes' and wait ~15-20 minutes
```

### Step 9.2: Connect and Verify

```bash
aws eks update-kubeconfig \
  --name devsecops-prod-cluster \
  --region us-east-1

# Should show 3 nodes
kubectl get nodes

# Check all security tools
kubectl get pods -n security-tools
kubectl get pods -n monitoring
kubectl get pods -n gatekeeper-system
```

### Step 9.3: Install ArgoCD on Production

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f kubernetes/argocd/argocd-values.yaml \
  -f kubernetes/argocd/helm-values/values-prod.yaml \
  --wait \
  --timeout 5m
```

### Step 9.4: Verify Strict Production Policies

```bash
# Check that prod Kustomize uses the strictest settings
cd ~/devsecops-platform-eks
kubectl kustomize kubernetes/overlays/prod/
```

Notice:
- All OPA constraints have `enforcementAction: deny` (no relaxation patches)
- Alert thresholds are the tightest (from the base, no patches)
- Pod Security Standard is `restricted` (strictest level)

### Step 9.5: Test Production OPA Enforcement

In production, OPA constraints DENY (not just warn). Let's verify:

```bash
# Try deploying a pod without required labels (should be BLOCKED)
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-no-labels
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
EOF
```

You should see an error like:
```
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
[require-mandatory-labels] Missing required labels: app.kubernetes.io/name, ...
```

This proves that production's OPA policies are actively blocking non-compliant deployments.

> **Checkpoint:** All 3 environments running! Dev (relaxed) → Staging (moderate) → Prod (strict)! Move to Phase 10!

---

## Phase 10: Test the CI/CD Pipeline End-to-End

Now let's test the complete flow: push code → CI/CD builds → deploys to correct environment.

### Step 10.1: Make a Change

Let's add a new required label to the OPA policy:

```bash
cd ~/devsecops-platform-eks
git checkout develop
```

Edit `kubernetes/base/security-policies/opa-constraints.yaml` — find the `parameters.labels` section in the `require-mandatory-labels` constraint and add a new label:

```yaml
  parameters:
    labels:
      - "app.kubernetes.io/name"
      - "app.kubernetes.io/managed-by"
      - "environment"
      - "team"                          # ← ADD THIS LINE
```

### Step 10.2: Push to Develop (Deploys to Dev)

```bash
git add kubernetes/base/security-policies/opa-constraints.yaml
git commit -m "Add team label requirement to OPA policy"
git push origin develop
```

Now watch GitHub Actions:
1. Go to your fork on GitHub → **Actions** tab
2. You should see a new workflow run triggered by the push to `develop`
3. Watch it progress through: Lint → Security Scan → Build → Deploy (dev only)

> **Note:** The deploy stage will fail if you haven't set up the GitHub Actions secrets
> from Phase 2. That's okay — the lint and security scan stages will still run and
> give you valuable feedback.

### Step 10.3: Promote to Staging

```bash
git checkout staging
git merge develop
git push origin staging
```

Watch GitHub Actions again — this time the deploy stage targets staging.

### Step 10.4: Promote to Production

```bash
git checkout master
git merge staging
git push origin master
```

Watch the final deployment to production.

### Step 10.5: Verify the Change Propagated

```bash
# Switch to each cluster and check the constraint
# Dev cluster
kubectl config use-context <dev-context>
kubectl get constraint require-mandatory-labels -o yaml | grep -A5 labels

# Staging cluster
kubectl config use-context <staging-context>
kubectl get constraint require-mandatory-labels -o yaml | grep -A5 labels

# Prod cluster
kubectl config use-context <prod-context>
kubectl get constraint require-mandatory-labels -o yaml | grep -A5 labels
```

All three should now show the `team` label in the required labels list.

> **Congratulations!** You've just completed the entire DevSecOps lifecycle:
> Code change → CI/CD → Dev → Staging → Production!

---

## Appendix A: Cost Estimates

### Estimated Monthly Cost Per Environment

| Resource | Dev | Staging | Prod |
|----------|-----|---------|------|
| EKS Control Plane | $73 | $73 | $73 |
| EC2 Nodes (1x t3.medium) | $30 | — | — |
| EC2 Nodes (2x t3.large) | — | $121 | — |
| EC2 Nodes (3x t3.xlarge) | — | — | $365 |
| NAT Gateways (3x) | $97 | $97 | $97 |
| EBS Storage | ~$10 | ~$15 | ~$25 |
| CloudWatch Logs | ~$5 | ~$5 | ~$10 |
| S3 + DynamoDB | <$1 | <$1 | <$1 |
| **Total/month** | **~$216** | **~$312** | **~$571** |
| **Total/day** | **~$7** | **~$10** | **~$19** |

> **All 3 environments: ~$36/day or ~$1,099/month**

### How to Minimize Costs

**Option 1: Only run dev** (~$7/day)
```bash
# Only deploy the dev environment for practice
# Skip Phases 8 and 9 entirely
```

**Option 2: Destroy when not practicing**
```bash
# At the end of your practice session:
cd terraform/environments/dev
terragrunt destroy    # Type 'yes' — takes ~10 minutes

# Next time you practice:
terragrunt apply      # Recreates everything (~20 minutes)
```

**Option 3: Reduce NAT Gateway costs**
The biggest "hidden" cost is NAT Gateways ($32/each/month x 3 AZs). For practice,
you could modify `terraform/modules/networking/main.tf` to use only 1 NAT Gateway
instead of 3.

---

## Appendix B: Complete Teardown

When you're done practicing, tear everything down to stop AWS charges.

> **IMPORTANT:** Follow this order. Destroying things out of order can leave orphaned resources that still cost money.

### Step 1: Remove ArgoCD Applications (Each Cluster)

For each cluster (dev, staging, prod):

```bash
# Switch to the cluster
kubectl config use-context <cluster-context>

# Delete ApplicationSets first (they manage Applications)
kubectl delete -f kubernetes/argocd/applicationsets.yaml --ignore-not-found
kubectl delete -f kubernetes/argocd/appproject.yaml --ignore-not-found

# Uninstall ArgoCD
helm uninstall argocd -n argocd
kubectl delete namespace argocd --ignore-not-found
```

### Step 2: Destroy Infrastructure (Reverse Order)

```bash
# Destroy prod first (most expensive)
cd terraform/environments/prod
terragrunt destroy
# Type 'yes' — wait ~10-15 minutes

# Destroy staging
cd ../staging
terragrunt destroy

# Destroy dev
cd ../dev
terragrunt destroy
```

### Step 3: Clean Up State Backend

```bash
# Empty and delete state buckets
for env in dev staging prod; do
  # Delete all versions (required for versioned buckets)
  aws s3api list-object-versions --bucket "devsecops-tfstate-${env}" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
    while read key version; do
      aws s3api delete-object --bucket "devsecops-tfstate-${env}" \
        --key "$key" --version-id "$version"
    done
  # Delete delete markers
  aws s3api list-object-versions --bucket "devsecops-tfstate-${env}" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | \
    while read key version; do
      aws s3api delete-object --bucket "devsecops-tfstate-${env}" \
        --key "$key" --version-id "$version"
    done
  # Delete the bucket
  aws s3 rb "s3://devsecops-tfstate-${env}"
done

# Delete DynamoDB table
aws dynamodb delete-table --table-name devsecops-terraform-locks
```

### Step 4: Clean Up IAM (Optional)

```bash
# Remove the GitHub OIDC role (if created)
# First detach all policies
for policy in AmazonEKSClusterPolicy AmazonVPCFullAccess AmazonEC2FullAccess \
  AmazonS3FullAccess IAMFullAccess CloudWatchFullAccess AWSKeyManagementServicePowerUser; do
  aws iam detach-role-policy --role-name github-actions-role \
    --policy-arn "arn:aws:iam::aws:policy/${policy}" 2>/dev/null
done
aws iam delete-role --role-name github-actions-role

# Remove the OIDC provider
OIDC_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn,'token.actions.githubusercontent.com')].Arn" \
  --output text)
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN"
```

### Step 5: Verify No Resources Remain

```bash
# Check for any remaining EKS clusters
aws eks list-clusters --region us-east-1

# Check for remaining VPCs (should only see the default VPC)
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}'

# Check for any remaining NAT Gateways (these cost money!)
aws ec2 describe-nat-gateways --region us-east-1 \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[].{Id:NatGatewayId,VpcId:VpcId}'
```

All queries should return empty arrays `[]`.

---

## Appendix C: Common Errors and Fixes

### Error: "The bucket does not exist"

```
Error: Failed to get existing workspaces: S3 bucket does not exist
```

**Cause:** The Terraform state bucket hasn't been created yet.
**Fix:** Go back to [Phase 3](#phase-3-create-terraform-state-backend) and create the S3 buckets.

### Error: "NAT Gateway limit exceeded"

```
Error: creating EC2 NAT Gateway: NatGatewayLimitExceeded
```

**Cause:** AWS accounts have a default limit of 5 NAT Gateways per AZ per region. If you have other infrastructure, you may hit this limit.
**Fix:**
```bash
# Request a limit increase via AWS Console:
# Service Quotas → Amazon VPC → NAT gateways per Availability Zone
# Or destroy unused NAT Gateways first
```

### Error: "EKS cluster creation timeout"

```
Error: waiting for EKS Cluster creation: timeout while waiting for state
```

**Cause:** EKS clusters can take up to 15 minutes to create. The default Terraform timeout may be too short.
**Fix:** Run `terragrunt apply` again — Terraform will see the cluster is already being created and wait for it.

### Error: "Helm release stuck in pending-install"

```
Error: release argocd failed, and has been uninstalled due to atomic being set: timed out
```

**Cause:** The cluster doesn't have enough resources, or pods are crash-looping.
**Fix:**
```bash
# Check what's happening
kubectl get pods -n argocd
kubectl describe pod <failing-pod-name> -n argocd
kubectl get events -n argocd --sort-by=.lastTimestamp

# Common fix: ensure nodes have enough capacity
kubectl get nodes -o wide
kubectl describe node <node-name> | grep -A5 "Allocated resources"
```

### Error: "OPA constraint template not ready"

```
Error from server: error when creating constraints: the server could not find the requested resource
```

**Cause:** You tried to create a Constraint before its ConstraintTemplate was ready.
**Fix:**
```bash
# Wait for constraint templates to be ready
kubectl wait --for=condition=established --timeout=60s \
  crd/constrainttemplates.templates.gatekeeper.sh

# Then retry applying constraints
kubectl apply -f kubernetes/base/security-policies/opa-constraints.yaml
```

### Error: "State lock held by another process"

```
Error: Error acquiring the state lock
```

**Cause:** A previous Terraform run crashed without releasing the lock.
**Fix:**
```bash
# First, make SURE no other terragrunt/terraform process is running
# Then force-unlock using the Lock ID from the error message
terragrunt force-unlock <LOCK_ID_FROM_ERROR>
```

### Error: "Insufficient capacity" when creating nodes

```
Error: creating EKS Node Group: InsufficientFreeAddressesInSubnet
```

**Cause:** The subnet doesn't have enough IP addresses for the requested nodes.
**Fix:** Check that your VPC CIDR is large enough (/16 provides 65,536 addresses, which is plenty). If using a smaller CIDR, increase it or reduce `node_max_size`.

### Error: kubectl connection refused

```
Unable to connect to the server: dial tcp: lookup ... no such host
```

**Cause:** Your kubeconfig is pointing to a cluster that doesn't exist or was destroyed.
**Fix:**
```bash
# Re-generate kubeconfig
aws eks update-kubeconfig --name devsecops-dev-cluster --region us-east-1

# Verify the cluster exists
aws eks describe-cluster --name devsecops-dev-cluster --region us-east-1
```

---

## What's Next?

Now that you have a working multi-environment platform, here are some exercises to deepen your understanding:

1. **Add a new OPA policy** — Create a constraint that requires all containers to set `readOnlyRootFilesystem: true`
2. **Create a custom Grafana dashboard** — Add a dashboard JSON to `kubernetes/base/monitoring/`
3. **Add a new alert** — Create a Prometheus alert rule in `prometheus-rules.yaml`
4. **Test incident response** — Run the `scripts/incident-response.py` script on a test pod
5. **Add a 4th environment** — Follow the runbook in [MULTI-ENV-GUIDE.md](MULTI-ENV-GUIDE.md#adding-a-new-environment-eg-qa) to add a "qa" environment
6. **Implement branch protection** — Set up GitHub branch protection rules requiring PR reviews before merging to `staging` or `master`

> **Read the [Multi-Environment Guide](MULTI-ENV-GUIDE.md)** for detailed explanations of how
> each component works and connects to the others.
