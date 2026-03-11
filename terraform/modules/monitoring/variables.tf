###############################################################################
# Monitoring Module — Variables
###############################################################################

# -----------------------------------------------------------------------------
# Cluster Reference
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https://)"
  type        = string
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring stack"
  type        = string
  default     = "monitoring"
}

# -----------------------------------------------------------------------------
# Prometheus Configuration
# -----------------------------------------------------------------------------

variable "prometheus_stack_version" {
  description = "Version of kube-prometheus-stack Helm chart"
  type        = string
  default     = "57.1.0"
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "15d"
}

variable "prometheus_retention_size" {
  description = "Maximum size of Prometheus TSDB storage"
  type        = string
  default     = "40GB"
}

variable "prometheus_replicas" {
  description = "Number of Prometheus replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.prometheus_replicas >= 1 && var.prometheus_replicas <= 5
    error_message = "Prometheus replicas must be between 1 and 5."
  }
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent volume size"
  type        = string
  default     = "50Gi"
}

# -----------------------------------------------------------------------------
# Alertmanager
# -----------------------------------------------------------------------------

variable "alertmanager_replicas" {
  description = "Number of Alertmanager replicas"
  type        = number
  default     = 2
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alert notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_critical_channel" {
  description = "Slack channel for critical alerts"
  type        = string
  default     = "#alerts-critical"
}

variable "slack_warning_channel" {
  description = "Slack channel for warning alerts"
  type        = string
  default     = "#alerts-warning"
}

# -----------------------------------------------------------------------------
# Grafana
# -----------------------------------------------------------------------------

variable "grafana_replicas" {
  description = "Number of Grafana replicas"
  type        = number
  default     = 1
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "grafana_ingress_enabled" {
  description = "Enable ingress for Grafana"
  type        = bool
  default     = false
}

variable "grafana_ingress_hosts" {
  description = "Hostnames for Grafana ingress"
  type        = list(string)
  default     = []
}

variable "grafana_certificate_arn" {
  description = "ACM certificate ARN for Grafana HTTPS ingress"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------

variable "cloudwatch_addon_version" {
  description = "Version of CloudWatch Observability Helm chart"
  type        = string
  default     = "1.5.0"
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------

variable "storage_class_name" {
  description = "Kubernetes StorageClass for persistent volumes"
  type        = string
  default     = "gp3"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
