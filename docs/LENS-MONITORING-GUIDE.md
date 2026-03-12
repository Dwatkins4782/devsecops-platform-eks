# Lens Kubernetes IDE: Cluster Management & Monitoring Guide

> **What is this?** A step-by-step guide to installing Lens (a visual Kubernetes IDE),
> connecting it to your EKS clusters, setting up real-time monitoring, querying metrics,
> and understanding how the entire monitoring stack works from end to end.
>
> **Prerequisites:** At least one deployed environment from the
> [Hands-On Setup Guide](HANDS-ON-SETUP-GUIDE.md). You need a running EKS cluster
> with the monitoring stack (Prometheus, Grafana, Alertmanager) already deployed.

---

## Table of Contents

1. [What is Lens and Why Use It?](#1-what-is-lens-and-why-use-it)
2. [Installing Lens](#2-installing-lens)
3. [Connecting Your EKS Clusters](#3-connecting-your-eks-clusters)
4. [Navigating and Managing Clusters in Lens](#4-navigating-and-managing-clusters-in-lens)
5. [Setting Up Monitoring in Lens](#5-setting-up-monitoring-in-lens)
6. [Querying Metrics Step-by-Step](#6-querying-metrics-step-by-step)
7. [Using Grafana Through Lens](#7-using-grafana-through-lens)
8. [How the Monitoring Stack Works](#8-how-the-monitoring-stack-works)
9. [Multi-Environment Monitoring Differences](#9-multi-environment-monitoring-differences)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. What is Lens and Why Use It?

### The Problem with kubectl

When you manage Kubernetes clusters with `kubectl`, you're typing commands and reading text output:

```bash
kubectl get pods -A                    # Wall of text
kubectl describe pod my-pod -n my-ns   # Even more text
kubectl logs my-pod -n my-ns           # Scrolling logs
kubectl top nodes                      # Numbers with no context
```

For beginners, this is overwhelming. You can't see relationships between resources, spot issues at a glance, or understand resource usage visually.

### What Lens Gives You

**Lens** is a free desktop application that acts as a visual dashboard for your Kubernetes clusters:

```
┌─────────────────────────────────────────────────────────────────────┐
│  LENS DESKTOP APPLICATION                                           │
│                                                                     │
│  ┌──────────┐  ┌─────────────────────────────────────────────────┐ │
│  │ CLUSTERS │  │                                                 │ │
│  │          │  │  Cluster Overview                               │ │
│  │ ● dev    │  │                                                 │ │
│  │ ● staging│  │  CPU ████████░░░░░░ 45%    Pods  42/110        │ │
│  │ ● prod   │  │  MEM ██████████░░░░ 67%    Nodes 3/3 Ready    │ │
│  │          │  │  DISK █████░░░░░░░░ 31%    Alerts 2 active     │ │
│  │          │  │                                                 │ │
│  │ WORKLOADS│  │  ┌─────────────────────────────────────────┐   │ │
│  │ Pods     │  │  │ Node CPU Usage (last 1h)                │   │ │
│  │ Deploys  │  │  │ ▂▃▅▇█▇▅▃▂▁▂▃▅▅▃▂▁▁▂▃▅▇▇▅▃▂▁          │   │ │
│  │ Services │  │  └─────────────────────────────────────────┘   │ │
│  │ ConfigMap│  │                                                 │ │
│  │ Secrets  │  │  ┌─────────────────────────────────────────┐   │ │
│  │          │  │  │ Memory Usage per Namespace               │   │ │
│  │ NETWORK  │  │  │ monitoring ████████░░ 2.1Gi              │   │ │
│  │ Services │  │  │ security   █████░░░░░ 1.3Gi              │   │ │
│  │ Ingress  │  │  │ argocd     ████░░░░░░ 0.9Gi              │   │ │
│  │ NetPol   │  │  └─────────────────────────────────────────┘   │ │
│  └──────────┘  └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

**Key benefits:**
- **Visual cluster overview** — CPU, memory, disk usage at a glance with charts
- **Multi-cluster management** — Switch between dev/staging/prod in one click
- **Built-in Prometheus integration** — Real-time metrics graphs on every resource
- **Log streaming** — View pod logs in real-time with search and filtering
- **Terminal access** — Open a shell into any pod directly from the UI
- **Resource editing** — Edit YAML for any resource with syntax highlighting
- **Port forwarding** — One-click port-forward to services (Prometheus, Grafana, etc.)

---

## 2. Installing Lens

### Download Lens Desktop

Go to **https://k8slens.dev/** and download the installer for your platform.

### macOS

```bash
# Option 1: Download from website (recommended)
# Visit https://k8slens.dev/ and download the .dmg file

# Option 2: Homebrew
brew install --cask lens
```

After installing, open Lens from your Applications folder.

### Windows

```powershell
# Option 1: Download from website (recommended)
# Visit https://k8slens.dev/ and download the .exe installer

# Option 2: Chocolatey
choco install lens -y

# Option 3: Winget
winget install Mirantis.Lens
```

Run the installer and follow the prompts.

### Linux

```bash
# Option 1: Download .AppImage from https://k8slens.dev/

# Option 2: Snap
sudo snap install kontena-lens --classic

# Option 3: Debian/Ubuntu (.deb)
# Download the .deb from the website, then:
sudo dpkg -i Lens-*.deb
```

### First Launch

1. Open Lens
2. You'll be asked to create a free account or sign in — follow the prompts
3. You'll see the **Lens Catalog** — an empty screen where your clusters will appear

> **Checkpoint:** Lens is open and showing the Catalog screen? Move to Section 3!

---

## 3. Connecting Your EKS Clusters

Lens reads your `~/.kube/config` file to discover clusters. If you've already run `aws eks update-kubeconfig`, your clusters are already available.

### Step 3.1: Ensure Your Kubeconfig Has All Clusters

```bash
# Add each cluster to your kubeconfig (if not already done)
aws eks update-kubeconfig --name devsecops-dev-cluster --region us-east-1 --alias dev-cluster
aws eks update-kubeconfig --name devsecops-staging-cluster --region us-east-1 --alias staging-cluster
aws eks update-kubeconfig --name devsecops-prod-cluster --region us-east-1 --alias prod-cluster
```

> **The `--alias` flag** gives your clusters friendly names instead of long ARNs.

Verify all clusters are in your kubeconfig:

```bash
kubectl config get-contexts
```

You should see 3 entries:
```
CURRENT   NAME               CLUSTER                                     AUTHINFO
*         dev-cluster        arn:aws:eks:us-east-1:...:devsecops-dev     arn:aws:eks:...
          staging-cluster    arn:aws:eks:us-east-1:...:devsecops-stg     arn:aws:eks:...
          prod-cluster       arn:aws:eks:us-east-1:...:devsecops-prod    arn:aws:eks:...
```

### Step 3.2: Add Clusters to Lens

1. Open Lens
2. Click the **Catalog** icon (grid icon) in the left sidebar
3. Your clusters should appear automatically under **Clusters**
4. If they don't appear:
   - Click the **"+"** button or go to **File → Add Cluster**
   - Select **"Paste as Text"**
   - Paste the contents of your kubeconfig file:
     ```bash
     cat ~/.kube/config
     ```
   - Click **Add Cluster(s)**

### Step 3.3: Connect to a Cluster

1. In the Catalog, click on **dev-cluster**
2. Lens will attempt to connect — you'll see a spinning indicator
3. Once connected, you'll see the **Cluster Overview** dashboard

> **If connection fails:** Ensure your AWS credentials are active:
> ```bash
> aws sts get-caller-identity
> ```
> If your credentials have expired, refresh them and restart Lens.

### Step 3.4: Add All 3 Clusters for Multi-Environment View

Repeat the click-to-connect process for `staging-cluster` and `prod-cluster`.

You can now switch between clusters by clicking the cluster icons in Lens's left sidebar:

```
Left Sidebar:
  ● dev-cluster        ← Green dot = connected and healthy
  ● staging-cluster    ← Click to switch
  ● prod-cluster       ← Click to switch
```

> **Checkpoint:** All 3 clusters showing green dots in Lens? Move to Section 4!

---

## 4. Navigating and Managing Clusters in Lens

### The Lens Interface Layout

When you click into a cluster, you see this layout:

```
┌──────────────────────────────────────────────────────────┐
│  ← Sidebar (navigation)  │  Main Content Area            │
│                           │                               │
│  📊 Cluster               │  (Shows whatever you clicked  │
│  ├─ Overview              │   in the sidebar)             │
│  ├─ Nodes                 │                               │
│  └─ Namespaces            │                               │
│                           │                               │
│  🔧 Workloads             │                               │
│  ├─ Pods                  │                               │
│  ├─ Deployments           │                               │
│  ├─ StatefulSets          │                               │
│  ├─ DaemonSets            │                               │
│  ├─ Jobs                  │                               │
│  └─ CronJobs              │                               │
│                           │                               │
│  ⚙️ Configuration         │                               │
│  ├─ ConfigMaps            │                               │
│  ├─ Secrets               │                               │
│  └─ HPA                   │                               │
│                           │                               │
│  🌐 Network               │                               │
│  ├─ Services              │                               │
│  ├─ Endpoints             │                               │
│  ├─ Ingresses             │                               │
│  └─ Network Policies      │                               │
│                           │                               │
│  💾 Storage               │                               │
│  ├─ PersistentVolumes     │                               │
│  └─ PersistentVolumeClaims│                               │
│                           │                               │
│  🔐 Access Control        │                               │
│  ├─ ServiceAccounts       │                               │
│  ├─ Roles                 │                               │
│  ├─ ClusterRoles          │                               │
│  └─ RoleBindings          │                               │
│                           │                               │
│  📦 Custom Resources      │                               │
│  ├─ ConstraintTemplates   │  ← OPA Gatekeeper             │
│  ├─ Constraints           │  ← OPA Policies               │
│  ├─ PrometheusRules       │  ← Alert Rules                │
│  ├─ ServiceMonitors       │  ← Prometheus Targets          │
│  └─ Applications          │  ← ArgoCD Apps                 │
└──────────────────────────────────────────────────────────┘
```

### Reading Cluster State

**Cluster → Overview:**
Shows a dashboard with CPU/memory/disk usage charts, pod counts, node status, and namespace breakdown. This is your "at a glance" health check.

**Cluster → Nodes:**
Click on any node to see:
- CPU and memory usage over time (graphs)
- Pod list running on that node
- Conditions (Ready, DiskPressure, MemoryPressure)
- Labels, taints, and allocatable resources

**Workloads → Pods:**
The Pods view shows ALL pods across ALL namespaces. Key things to look at:

| Column | What It Means |
|--------|---------------|
| Status | ✅ Running, ⚠️ Pending, ❌ CrashLoopBackOff, etc. |
| Restarts | High number = something is wrong |
| CPU/Memory | Real-time resource usage (requires Prometheus) |
| Age | How long the pod has been running |
| Node | Which node the pod is on |

**How to filter by namespace:**
Click the namespace dropdown at the top of the pod list and select `monitoring`, `security-tools`, `argocd`, etc.

### Managing Resources

**Viewing pod logs:**
1. Click on any pod → **Logs** tab
2. Select the container (if multiple)
3. Logs stream in real-time with search capability
4. Click **Show Previous** to see logs from crashed containers

**Opening a shell into a pod:**
1. Click on any pod → **Terminal** icon (top right) or right-click → **Shell**
2. Select the container
3. A terminal opens inside the container — you can run commands directly

**Editing a resource:**
1. Click on any resource (pod, deployment, service, etc.)
2. Click the **pencil icon** (Edit) in the top right
3. Lens opens a YAML editor with syntax highlighting
4. Make changes and click **Save** — Lens runs `kubectl apply` for you

**Scaling a deployment:**
1. Go to **Workloads → Deployments**
2. Click on a deployment (e.g., `kube-prometheus-stack-grafana`)
3. Click the **Scale** button or click the pencil icon and change `spec.replicas`

**Deleting a resource:**
1. Right-click on any resource
2. Select **Delete** — Lens shows a confirmation dialog

> **Warning:** Be careful with delete operations, especially in production clusters.

### Viewing Our Security Resources

**Custom Resources → ConstraintTemplates:**
Shows all OPA Gatekeeper constraint templates (K8sRequiredLabels, K8sBlockLatestImages, K8sRequireResourceLimits)

**Custom Resources → Constraints:**
Shows all active constraints and their enforcement action (deny/warn)

**Network → Network Policies:**
Shows all zero-trust network policies across namespaces

---

## 5. Setting Up Monitoring in Lens

Lens has **built-in Prometheus integration** that overlays resource usage graphs directly on nodes and pods. Here's how to configure it.

### Step 5.1: Open Cluster Settings

1. Click on the cluster name in the left sidebar
2. Click the **gear icon** (⚙️) next to the cluster name, or right-click and choose **Settings**

### Step 5.2: Configure Prometheus

In the **Metrics** section of cluster settings:

1. **Prometheus Service Address:** Set this to our Prometheus service:
   ```
   monitoring/kube-prometheus-stack-prometheus:9090
   ```

   Format: `<namespace>/<service-name>:<port>`

   > **What this tells Lens:** "To get metrics, connect to the service called
   > `kube-prometheus-stack-prometheus` in the `monitoring` namespace on port 9090."

2. Click **Apply** or **Save**

### Step 5.3: Verify Metrics Are Working

After saving the Prometheus configuration:

1. Go to **Cluster → Nodes**
2. Click on any node
3. You should now see **live CPU and Memory charts** embedded in the node detail view
4. Go to **Workloads → Pods**
5. Each pod row should show tiny CPU/Memory sparkline charts

If you see flat lines or "No metrics available":
- Verify Prometheus is running: `kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus`
- Verify the service exists: `kubectl get svc -n monitoring kube-prometheus-stack-prometheus`
- Check the Lens setting matches the exact service name

### Step 5.4: What Metrics You Can Now See in Lens

Once Prometheus is connected, Lens shows metrics EVERYWHERE:

**Cluster Overview:**
- Total cluster CPU usage over time
- Total cluster memory usage over time
- Pod count over time
- Network received/transmitted

**Per Node (Cluster → Nodes → Click a node):**
- CPU usage (all cores combined) — line chart over time
- Memory usage (used vs total) — line chart over time
- Disk usage
- Network I/O
- Pod count on this node

**Per Pod (Workloads → Pods → Click a pod):**
- Container CPU usage — line chart
- Container memory usage (RSS, working set) — line chart
- Container network traffic
- Container filesystem read/write

**Per Namespace (Cluster → Namespaces → Click a namespace):**
- Aggregate CPU for all pods in that namespace
- Aggregate memory for all pods
- Pod count in namespace

### Step 5.5: Configure Monitoring for All 3 Clusters

Repeat Steps 5.1-5.3 for your staging and prod clusters. The Prometheus service name is the same in all environments:

```
monitoring/kube-prometheus-stack-prometheus:9090
```

Now when you switch between clusters in Lens, each one shows its own independent metrics.

---

## 6. Querying Metrics Step-by-Step

### Accessing the Prometheus UI

**Method 1: Port-forward via Lens (Easiest)**
1. In Lens, go to **Network → Services**
2. Find `kube-prometheus-stack-prometheus` in the `monitoring` namespace
3. Click on it → click the **Forward** icon (or right-click → **Port Forward**)
4. Set Local Port to `9090` and click **Start**
5. Click the link that appears — Prometheus opens in your browser at `http://localhost:9090`

**Method 2: Command line**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```
Then open http://localhost:9090

### PromQL Basics for Beginners

PromQL (Prometheus Query Language) is how you ask Prometheus questions about your metrics. Let's start from the basics.

**What is a metric?**
A metric is a measurement that Prometheus collects periodically (every 30 seconds in our setup). Think of it like a sensor reading.

```
Example metric: node_cpu_seconds_total

This records total CPU time used. Prometheus stores it with labels:
  node_cpu_seconds_total{cpu="0", mode="idle", instance="10.10.1.5:9100"}
  node_cpu_seconds_total{cpu="0", mode="user", instance="10.10.1.5:9100"}
  node_cpu_seconds_total{cpu="1", mode="idle", instance="10.10.1.5:9100"}
```

**What are labels?**
Labels are key-value pairs inside `{}` that let you filter metrics. Think of them as tags or categories.

**Basic query syntax:**
```
metric_name                              # All values of this metric
metric_name{label="value"}              # Filter by label
metric_name{label=~"val1|val2"}         # Regex filter (match val1 OR val2)
metric_name{label!="value"}             # Exclude a value
```

**Key PromQL functions:**
```
rate(metric[5m])        # Rate of change over 5 minutes (for counters)
increase(metric[1h])    # Total increase over 1 hour
sum(metric)             # Add up all values
avg(metric)             # Average across all values
topk(10, metric)        # Top 10 values
histogram_quantile(0.99, metric)  # 99th percentile
```

### Essential Queries by Category

Open the Prometheus UI (http://localhost:9090) and paste these queries into the **Expression** box. Click **Execute** and then switch to the **Graph** tab to see charts.

#### Infrastructure Queries

**CPU usage per node (percentage):**
```promql
(1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100
```
> Translation: "For each node, calculate how much CPU is NOT idle over the last 5 minutes, as a percentage."

**Memory usage per node (percentage):**
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```
> Translation: "For each node, what percentage of memory is being used?"

**Disk usage per node (percentage):**
```promql
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100
```

**Network traffic per node (bytes/sec received):**
```promql
rate(node_network_receive_bytes_total{device!="lo"}[5m])
```

**Pod CPU usage (top 10 pods):**
```promql
topk(10, sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m])))
```

**Pod memory usage (top 10 pods):**
```promql
topk(10, sum by (namespace, pod) (container_memory_working_set_bytes{container!=""}))
```

#### Security Queries

**Falco critical events in the last 24 hours:**
```promql
sum(increase(falco_events{priority="Critical"}[24h])) or vector(0)
```
> Translation: "How many critical Falco events happened in the last 24 hours? If none, show 0."

**Falco events by priority (rate per minute):**
```promql
sum by (priority) (rate(falco_events[5m]) * 60)
```

**Falco events by rule (top 10 in last hour):**
```promql
topk(10, sum by (rule) (increase(falco_events[1h])))
```

**OPA Gatekeeper total violations:**
```promql
sum(gatekeeper_violations) or vector(0)
```

**OPA violations by constraint:**
```promql
sum by (constraint_name) (gatekeeper_violations)
```

**OPA webhook denial rate (per minute):**
```promql
sum(rate(gatekeeper_admission_webhook_denied_total[5m])) * 60
```

**Trivy critical vulnerabilities across all images:**
```promql
sum(trivy_image_vulnerabilities{severity="Critical"}) or vector(0)
```

**Trivy vulnerabilities by severity:**
```promql
sum by (severity) (trivy_image_vulnerabilities)
```

**Most vulnerable images (top 20):**
```promql
topk(20, sum by (image_repository, image_tag) (trivy_image_vulnerabilities{severity="Critical"}))
```

**Unauthorized API access attempts (last hour):**
```promql
sum(increase(apiserver_audit_event_total{code=~"401|403"}[1h])) or vector(0)
```

#### Kubernetes Health Queries

**Pod restart count (last hour, by pod):**
```promql
increase(kube_pod_container_status_restarts_total[1h]) > 0
```

**Pods not in Running state:**
```promql
kube_pod_status_phase{phase!="Running",phase!="Succeeded"} == 1
```

**Deployments not at desired replica count:**
```promql
kube_deployment_status_replicas_available != kube_deployment_spec_replicas
```

**Nodes not ready:**
```promql
kube_node_status_condition{condition="Ready",status="true"} == 0
```

**API server request latency (99th percentile, by verb):**
```promql
histogram_quantile(0.99, sum by (le, verb) (rate(apiserver_request_duration_seconds_bucket[5m])))
```

**API server request rate (per second):**
```promql
sum by (verb) (rate(apiserver_request_total[5m]))
```

#### ArgoCD Queries

**ArgoCD application sync status:**
```promql
argocd_app_info
```

**ArgoCD sync operations (per minute):**
```promql
sum(rate(argocd_app_sync_total[5m])) * 60
```

**ArgoCD server HTTP request rate:**
```promql
sum by (code) (rate(argocd_server_http_requests_total[5m]))
```

### Query Tips

1. **Always use `or vector(0)`** for sum/count queries — this returns 0 instead of "no data" when there are no matches
2. **Use `[5m]` ranges** for rate calculations — too short (1m) is noisy, too long (1h) is too smooth
3. **Use the Graph tab** in Prometheus to see trends over time, not just instant values
4. **Click Execute** after each query — Prometheus doesn't auto-run

---

## 7. Using Grafana Through Lens

Grafana provides pre-built dashboards that are much richer than raw Prometheus queries.

### Step 7.1: Port-Forward Grafana from Lens

1. In Lens, go to **Network → Services**
2. Find `kube-prometheus-stack-grafana` in the `monitoring` namespace
3. Right-click → **Port Forward**
4. Set Local Port to `3000`, Remote Port to `80`
5. Click **Start**
6. Click the link — Grafana opens at `http://localhost:3000`

### Step 7.2: Log Into Grafana

- **Username:** `admin`
- **Password:** Retrieve it from the cluster:
  ```bash
  kubectl get secret -n monitoring kube-prometheus-stack-grafana \
    -o jsonpath='{.data.admin-password}' | base64 --decode; echo
  ```

### Step 7.3: Explore Pre-Built Dashboards

Click **Dashboards** (four squares icon) in Grafana's left sidebar. You'll see categories:

**Default dashboards from kube-prometheus-stack:**
- `Kubernetes / Compute Resources / Cluster` — Cluster-wide CPU/memory
- `Kubernetes / Compute Resources / Namespace (Pods)` — Per-namespace breakdown
- `Kubernetes / Compute Resources / Node (Pods)` — Per-node breakdown
- `Kubernetes / Compute Resources / Pod` — Individual pod detail
- `Kubernetes / Networking / Cluster` — Network traffic
- `Node Exporter / Nodes` — Detailed host-level metrics
- `Prometheus / Overview` — Prometheus self-monitoring

**Our custom security dashboard:**
- `DevSecOps Security Overview` — The dashboard we created with Falco, OPA, Trivy, and API security panels

### Step 7.4: Using the Security Dashboard

1. Navigate to **Dashboards → DevSecOps Security Overview**
2. The dashboard has 5 rows of panels:

**Row 1 — Security Overview Stats (4 stat panels):**
| Panel | What It Shows | Good | Bad |
|-------|--------------|------|-----|
| Falco Critical Events (24h) | Runtime security threats in last day | 0 (green) | > 5 (red) |
| Gatekeeper Violations | Active policy violations right now | 0 (green) | > 50 (red) |
| Critical CVEs in Cluster | Unpatched critical vulnerabilities | 0 (green) | > 1 (red) |
| Unauthorized API Requests (1h) | Failed auth attempts | 0 (green) | > 20 (red) |

**Row 2 — Falco Runtime Security:**
- Events by Priority — bar chart showing Critical vs Warning vs Notice events over time
- Events by Rule (Top 10) — which Falco rules are firing most

**Row 3 — OPA Gatekeeper:**
- Violations by Constraint — which policies are being violated
- Admission Webhook Deny Rate — how many deployments are being blocked per minute

**Row 4 — Trivy Vulnerabilities:**
- Vulnerabilities by Severity — stacked bar (Critical, High, Medium, Low)
- Most Vulnerable Images — table of the top 20 riskiest container images

**Row 5 — Cluster Security Posture:**
- API Server Request Latency (p99) — slow API responses may indicate attacks
- Pod Security Violations — namespace-level policy enforcement activity

3. Use the **Namespace** dropdown at the top to filter to a specific namespace
4. Change the time range (top right) to zoom in/out (e.g., "Last 1 hour", "Last 24 hours")

### Step 7.5: Creating Your Own Dashboard

1. Click **Dashboards → New Dashboard**
2. Click **Add Visualization**
3. Select **Prometheus** as the data source
4. Paste any PromQL query from [Section 6](#6-querying-metrics-step-by-step) into the query field
5. Choose a visualization type (Time Series, Stat, Gauge, Table, etc.)
6. Click **Apply**
7. Click the **floppy disk icon** to save your dashboard

**Example: Create a "Cluster Resource Usage" dashboard:**

Panel 1 (Gauge): Node CPU Usage
```promql
avg(1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100
```

Panel 2 (Gauge): Node Memory Usage
```promql
avg(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

Panel 3 (Time Series): Pod CPU by Namespace
```promql
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
```

Panel 4 (Table): Top Pods by Memory
```promql
topk(10, sum by (namespace, pod) (container_memory_working_set_bytes{container!=""}))
```

---

## 8. How the Monitoring Stack Works

This section explains the complete monitoring architecture from the ground up.

### 8.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MONITORING DATA FLOW                                │
│                                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌─────────────┐ │
│  │ Node Exporter │   │ kube-state-  │   │  Falco       │   │ Trivy       │ │
│  │ (per node)    │   │ metrics      │   │ (per node)   │   │ Operator    │ │
│  │               │   │              │   │              │   │             │ │
│  │ CPU, Memory,  │   │ Pod counts,  │   │ Runtime      │   │ Vuln scan   │ │
│  │ Disk, Network │   │ Deploy status│   │ security     │   │ results     │ │
│  │ Host metrics  │   │ Node status  │   │ events       │   │ Config audit│ │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘   └──────┬──────┘ │
│         │                   │                   │                   │        │
│         │  ServiceMonitor   │  ServiceMonitor   │  ServiceMonitor   │        │
│         │  auto-discovery   │                   │                   │        │
│         v                   v                   v                   v        │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        PROMETHEUS                                    │   │
│  │                                                                      │   │
│  │  1. SCRAPE: Every 30 seconds, pulls metrics from all targets         │   │
│  │  2. STORE:  Saves metrics to local disk (50Gi, 15-day retention)     │   │
│  │  3. EVALUATE: Runs PromQL alert rules every 30 seconds               │   │
│  │  4. ALERT: Fires alerts when rules match                             │   │
│  │                                                                      │   │
│  │  Storage: 50Gi PersistentVolume (gp3 SSD)                           │   │
│  │  Retention: 15 days (prod) / 3 days (dev)                           │   │
│  │  Replicas: 2 (prod) / 1 (dev)                                      │   │
│  └───────┬────────────────────────┬─────────────────────────────────────┘   │
│          │                        │                                         │
│          │ Query (PromQL)         │ Alert (fired rules)                     │
│          v                        v                                         │
│  ┌───────────────┐    ┌──────────────────────────────────────────────┐      │
│  │   GRAFANA     │    │              ALERTMANAGER                    │      │
│  │               │    │                                              │      │
│  │ Dashboards:   │    │  1. RECEIVE: Gets alerts from Prometheus     │      │
│  │ - Cluster     │    │  2. GROUP:   Batches related alerts          │      │
│  │ - Security    │    │  3. ROUTE:   Routes by severity              │      │
│  │ - Nodes       │    │  4. NOTIFY:  Sends to Slack channels         │      │
│  │               │    │                                              │      │
│  │ Auto-refresh  │    │  Critical → #alerts-critical (every 1h)      │      │
│  │ every 30 sec  │    │  Warning  → #alerts-warning  (every 4h)      │      │
│  └───────────────┘    └──────────────────────────────────────────────┘      │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        CLOUDWATCH (Dual Layer)                       │   │
│  │                                                                      │   │
│  │  Parallel monitoring path for AWS-native integration:                │   │
│  │  - Container stdout/stderr logs → CloudWatch Logs                    │   │
│  │  - Node metrics → CloudWatch Metrics                                 │   │
│  │  - EKS control plane logs → CloudWatch audit trail                   │   │
│  │                                                                      │   │
│  │  Why both? Prometheus for detailed metrics + dashboards.             │   │
│  │  CloudWatch for AWS-native integration + long-term log retention.    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 What Each Component Does

#### Prometheus (The Engine)

**What it is:** A time-series database that collects and stores metrics.

**How it collects data:** Prometheus uses a **pull model** — it reaches out to targets and "scrapes" their metrics endpoints every 30 seconds.

```
Prometheus → GET http://node-exporter:9100/metrics → Gets CPU/memory data
Prometheus → GET http://falco:8765/metrics          → Gets security events
Prometheus → GET http://gatekeeper:8888/metrics      → Gets policy violations
```

**How it discovers targets:** Instead of hardcoding target URLs, Prometheus uses **ServiceMonitor** resources. Our Terraform code creates ServiceMonitors that say "scrape this service at this port." Prometheus auto-discovers all ServiceMonitors in the cluster.

```yaml
# ServiceMonitor tells Prometheus: "Scrape Falco metrics"
kind: ServiceMonitor
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: falco    # Find the Falco service
  endpoints:
    - port: metrics                     # Scrape this port
      interval: 30s                     # Every 30 seconds
```

**How it stores data:** Metrics are stored as time-series on a PersistentVolume:
- Each data point = timestamp + value + labels
- Retention: 15 days (prod), configurable per environment
- Storage: 50Gi gp3 SSD volume

#### Node Exporter (Host Metrics)

**What it is:** A DaemonSet (runs on every node) that exposes hardware/OS metrics.

**What it provides:**
- `node_cpu_seconds_total` — CPU time per core per mode (user, system, idle)
- `node_memory_MemTotal_bytes` — Total RAM
- `node_memory_MemAvailable_bytes` — Available RAM
- `node_filesystem_size_bytes` — Disk size
- `node_filesystem_avail_bytes` — Free disk space
- `node_network_receive_bytes_total` — Network bytes received
- `node_network_transmit_bytes_total` — Network bytes sent

#### kube-state-metrics (Kubernetes Object Metrics)

**What it is:** A single deployment that watches the Kubernetes API and exposes object state as metrics.

**What it provides:**
- `kube_pod_info` — Pod metadata (namespace, node, IP)
- `kube_pod_status_phase` — Pod phase (Pending, Running, Failed)
- `kube_pod_container_status_restarts_total` — Container restart count
- `kube_deployment_spec_replicas` — Desired replica count
- `kube_deployment_status_replicas_available` — Actual running replicas
- `kube_node_status_condition` — Node conditions (Ready, DiskPressure)

#### Grafana (Visualization)

**What it is:** A dashboarding tool that queries Prometheus and renders charts.

**How it works:**
1. Grafana sends PromQL queries to Prometheus's HTTP API
2. Prometheus returns time-series data
3. Grafana renders it as charts, gauges, tables, etc.
4. Auto-refreshes every 30 seconds

**Dashboard discovery:** Grafana has a "sidecar" container that watches ALL namespaces for ConfigMaps labeled `grafana_dashboard: "true"` and automatically loads them as dashboards.

#### Alertmanager (Notification Routing)

**What it is:** Receives alerts from Prometheus and routes them to notification channels.

**How the alert pipeline works:**

```
Step 1: Prometheus evaluates a rule every 30 seconds
        Example: "Is node CPU > 90% for 15 minutes?"
                ↓
Step 2: If the condition is TRUE for the "for" duration,
        Prometheus FIRES the alert and sends it to Alertmanager
                ↓
Step 3: Alertmanager GROUPS related alerts
        (e.g., 3 nodes with high CPU become 1 grouped alert)
        Waits 30 seconds for more alerts to arrive (group_wait)
                ↓
Step 4: Alertmanager ROUTES the alert based on severity label:
        severity: critical → #alerts-critical Slack channel
        severity: warning  → #alerts-warning Slack channel
                ↓
Step 5: Alertmanager SENDS the notification
        Includes: alert name, summary, affected resource, link to Grafana
                ↓
Step 6: If the alert is still firing, Alertmanager RE-SENDS:
        Critical: every 1 hour
        Warning: every 4 hours
                ↓
Step 7: When the condition is no longer true, Prometheus sends
        a RESOLVED notification to Alertmanager, which forwards
        it to Slack so you know the issue is fixed
```

#### CloudWatch (AWS-Native Layer)

**What it is:** AWS's built-in monitoring service running in parallel with Prometheus.

**Why we use BOTH Prometheus and CloudWatch:**

| Feature | Prometheus | CloudWatch |
|---------|-----------|------------|
| Custom metrics | Excellent (PromQL) | Limited |
| Custom dashboards | Grafana | CloudWatch Dashboards |
| Real-time alerting | Alertmanager (flexible) | CloudWatch Alarms (simpler) |
| Log aggregation | Not built-in | Excellent (CloudWatch Logs) |
| AWS integration | Manual | Native (EKS, IAM, S3) |
| Long-term retention | 15 days (in our setup) | Months/years |
| Cost | Free (runs on cluster) | Pay per metric/log |

**Prometheus** = Deep application and security metrics with powerful querying.
**CloudWatch** = AWS-native logs, long-term retention, and compliance audit trail.

### 8.3 The Complete Alert Lifecycle (Example)

Let's follow a real alert through the entire system:

**Scenario:** A developer accidentally deploys a container that mines cryptocurrency, causing high CPU usage.

```
Minute 0:00  — Crypto miner starts, CPU spikes to 95%
               Node Exporter scrapes: node_cpu_seconds_total jumps

Minute 0:30  — Prometheus scrapes Node Exporter
               Evaluates rule: "(1 - idle_rate) > 90%"
               Condition is TRUE, but "for: 15m" hasn't elapsed yet
               Alert state: PENDING

Minute 0:30  — Falco detects unusual process execution
               Falco event: priority=Critical, rule="Launch Crypto Miner"
               falco_events{priority="Critical"} increases

Minute 1:00  — Prometheus scrapes Falco metrics
               Evaluates FalcoCriticalAlert rule: increase > 0
               Since "for: 0m", alert FIRES immediately!

               Prometheus → Alertmanager:
               {alertname="FalcoCriticalAlert", severity="critical",
                category="runtime-security"}

Minute 1:30  — Alertmanager groups the alert (waits 30s for more)
               Routes to "critical-alerts" receiver
               Sends Slack message to #alerts-critical:

               🚨 [CRITICAL] FalcoCriticalAlert
               Summary: Falco critical security event detected
               Description: Falco detected 1 critical event(s) in the last 5 minutes
               Namespace: default
               Dashboard: http://grafana:3000/d/devsecops-security-overview

Minute 15:00 — CPU has been > 90% for 15 minutes
               NodeHighCPUUsage alert FIRES
               Alertmanager sends another Slack notification:

               ⚠️ [WARNING] NodeHighCPUUsage
               Summary: Node CPU usage above 90%
               Description: Node 10.10.1.5 CPU usage is 95%

Minute 15:30 — Platform engineer sees Slack alerts
               Opens Lens → Cluster Overview → sees red CPU chart
               Opens Grafana Security Dashboard → sees Falco critical event
               Clicks into Falco Events by Rule → sees "Launch Crypto Miner"
               Uses Lens Terminal to shell into the pod → kills the process
               Deletes the malicious pod

Minute 16:00 — CPU drops back to normal
               Prometheus evaluates rules → conditions no longer TRUE
               Sends RESOLVED to Alertmanager
               Alertmanager sends to Slack:

               ✅ [RESOLVED] FalcoCriticalAlert
               ✅ [RESOLVED] NodeHighCPUUsage
```

---

## 9. Multi-Environment Monitoring Differences

Our Kustomize overlays adjust monitoring thresholds per environment:

### Alert Threshold Comparison

| Alert | Dev | Staging | Prod |
|-------|-----|---------|------|
| **FalcoCriticalAlert** | > 3 events in 10m, wait 5m | > 0 events in 5m, wait 2m | > 0 events in 5m, immediate |
| **NodeHighCPUUsage** | > 98%, wait 30m | > 95%, wait 30m | > 90%, wait 15m |
| **NodeHighMemoryUsage** | > 95%, wait 30m | (base default) | > 90%, wait 15m |
| **PodCrashLooping** | > 20 restarts/hr, wait 30m | > 10 restarts/hr, wait 15m | > 5 restarts/hr, wait 10m |
| **GatekeeperViolations** | Present (warn) | Present (warn) | Present, immediate (critical) |

### Why Different Thresholds?

**Dev (very relaxed):**
- Developers are building and breaking things constantly
- Single-node cluster can easily hit 98% CPU during builds
- Pods crash-loop while debugging — that's expected
- Alert fatigue is the real enemy in dev

**Staging (moderate):**
- Closer to production behavior
- Still allows some slack for testing
- Catches real issues before they hit production

**Prod (tight):**
- Any anomaly could affect real users
- Immediate alerts for security events
- Low thresholds catch issues early
- Self-healing ArgoCD reverts unauthorized changes

---

## 10. Troubleshooting

### Lens Shows "No Metrics Available"

**Cause:** Lens can't reach the Prometheus service.
**Fix:**
1. Check Prometheus is running:
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
   ```
2. Check the service exists:
   ```bash
   kubectl get svc -n monitoring kube-prometheus-stack-prometheus
   ```
3. Verify the Lens cluster settings have the correct address:
   ```
   monitoring/kube-prometheus-stack-prometheus:9090
   ```
4. Try restarting Lens (close and reopen)

### Grafana Shows "No Data" on Dashboard Panels

**Cause:** The metric doesn't exist yet (e.g., no Falco events have occurred).
**Fix:** This is normal for security metrics. If no Falco events have been triggered, `falco_events` won't have data. Our queries use `or vector(0)` to show 0 instead of "no data".

To generate test data:
```bash
# Trigger a Falco event by running a shell in a container
kubectl run test-falco --image=alpine --rm -it -- sh -c "cat /etc/shadow"
# This should trigger Falco's "Read Sensitive Files" rule
kubectl delete pod test-falco --ignore-not-found
```

### Prometheus Returns "query processing would load too many samples"

**Cause:** Your query has too wide a time range or too many series.
**Fix:** Narrow the query:
```promql
# Instead of this (all pods, all time):
container_cpu_usage_seconds_total

# Use this (specific namespace, specific time range):
rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m])
```

### Alertmanager Not Sending Slack Notifications

**Cause:** Slack webhook URL not configured or invalid.
**Fix:**
1. Check Alertmanager config:
   ```bash
   kubectl get secret -n monitoring kube-prometheus-stack-alertmanager \
     -o jsonpath='{.data.alertmanager\.yaml}' | base64 --decode
   ```
2. Verify the Slack webhook URL is present and valid
3. Test the webhook manually:
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test from Alertmanager"}' \
     YOUR_SLACK_WEBHOOK_URL
   ```

### Lens Can't Connect to EKS Cluster

**Cause:** AWS credentials expired or kubeconfig is stale.
**Fix:**
```bash
# Refresh credentials
aws sts get-caller-identity  # Check if creds work

# Regenerate kubeconfig
aws eks update-kubeconfig --name devsecops-dev-cluster --region us-east-1

# Restart Lens
```

### Prometheus Disk Full / Storage Issues

**Cause:** Metrics volume is filling up faster than expected.
**Fix:**
```bash
# Check PVC usage
kubectl get pvc -n monitoring

# Check actual disk usage
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 \
  -- df -h /prometheus

# If full, reduce retention in terraform/modules/monitoring/main.tf:
# prometheus_retention = "7d" (reduce from 15d)
# prometheus_retention_size = "30GB" (reduce from 40GB)
# Then: terragrunt apply
```

---

## Quick Reference Card

```
LENS PROMETHEUS SETTING:
  monitoring/kube-prometheus-stack-prometheus:9090

PORT-FORWARD COMMANDS:
  Prometheus:   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
  Grafana:      kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
  Alertmanager: kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

GRAFANA LOGIN:
  User: admin
  Pass: kubectl get secret -n monitoring kube-prometheus-stack-grafana \
        -o jsonpath='{.data.admin-password}' | base64 --decode

TOP 5 SECURITY QUERIES:
  Falco criticals:    sum(increase(falco_events{priority="Critical"}[24h]))
  OPA violations:     sum(gatekeeper_violations)
  Critical CVEs:      sum(trivy_image_vulnerabilities{severity="Critical"})
  Unauth API calls:   sum(increase(apiserver_audit_event_total{code=~"401|403"}[1h]))
  Pod crash loops:    increase(kube_pod_container_status_restarts_total[1h]) > 5

TOP 5 INFRASTRUCTURE QUERIES:
  Node CPU %:         (1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100
  Node Memory %:      (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
  Top pods (CPU):     topk(10, sum by(namespace,pod)(rate(container_cpu_usage_seconds_total[5m])))
  Top pods (Memory):  topk(10, sum by(namespace,pod)(container_memory_working_set_bytes))
  Unhealthy nodes:    kube_node_status_condition{condition="Ready",status="true"} == 0
```
