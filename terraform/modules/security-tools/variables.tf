###############################################################################
# Security Tools Module — Variables
###############################################################################

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

variable "security_namespace" {
  description = "Kubernetes namespace for security tools"
  type        = string
  default     = "security-tools"
}

# -----------------------------------------------------------------------------
# Falco Configuration
# -----------------------------------------------------------------------------

variable "falco_version" {
  description = "Falco Helm chart version"
  type        = string
  default     = "4.2.2"
}

variable "falco_driver_kind" {
  description = "Falco driver type: modern_ebpf, ebpf, or module"
  type        = string
  default     = "modern_ebpf"

  validation {
    condition     = contains(["modern_ebpf", "ebpf", "module"], var.falco_driver_kind)
    error_message = "Falco driver must be modern_ebpf, ebpf, or module."
  }
}

variable "falco_log_level" {
  description = "Falco logging level"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["emergency", "alert", "critical", "error", "warning", "notice", "info", "debug"], var.falco_log_level)
    error_message = "Invalid Falco log level."
  }
}

variable "falco_minimum_priority" {
  description = "Minimum alert priority for Falco events"
  type        = string
  default     = "notice"
}

variable "falco_http_output_enabled" {
  description = "Enable HTTP output for Falco alerts"
  type        = bool
  default     = false
}

variable "falco_http_output_url" {
  description = "URL for Falco HTTP alert output"
  type        = string
  default     = ""
}

variable "enable_falcosidekick" {
  description = "Deploy Falcosidekick for alert routing"
  type        = bool
  default     = true
}

variable "enable_falcosidekick_ui" {
  description = "Deploy Falcosidekick UI for event visualization"
  type        = bool
  default     = true
}

variable "falco_slack_channel" {
  description = "Slack channel for Falco alerts"
  type        = string
  default     = "#security-alerts"
}

# -----------------------------------------------------------------------------
# Trivy Operator Configuration
# -----------------------------------------------------------------------------

variable "trivy_operator_version" {
  description = "Trivy Operator Helm chart version"
  type        = string
  default     = "0.21.4"
}

variable "trivy_severity_levels" {
  description = "Vulnerability severity levels to report"
  type        = string
  default     = "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL"
}

variable "trivy_ignore_unfixed" {
  description = "Ignore vulnerabilities with no available fix"
  type        = bool
  default     = false
}

variable "trivy_concurrent_scans" {
  description = "Maximum number of concurrent vulnerability scans"
  type        = number
  default     = 10

  validation {
    condition     = var.trivy_concurrent_scans >= 1 && var.trivy_concurrent_scans <= 30
    error_message = "Concurrent scans must be between 1 and 30."
  }
}

variable "trivy_compliance_cron" {
  description = "Cron schedule for compliance report generation"
  type        = string
  default     = "0 1 * * *"
}

# -----------------------------------------------------------------------------
# OPA Gatekeeper Configuration
# -----------------------------------------------------------------------------

variable "gatekeeper_version" {
  description = "OPA Gatekeeper Helm chart version"
  type        = string
  default     = "3.15.1"
}

variable "gatekeeper_replicas" {
  description = "Number of Gatekeeper controller replicas"
  type        = number
  default     = 3

  validation {
    condition     = var.gatekeeper_replicas >= 1 && var.gatekeeper_replicas <= 5
    error_message = "Gatekeeper replicas must be between 1 and 5."
  }
}

variable "gatekeeper_audit_interval" {
  description = "Audit interval in seconds for Gatekeeper"
  type        = number
  default     = 60

  validation {
    condition     = var.gatekeeper_audit_interval >= 30 && var.gatekeeper_audit_interval <= 3600
    error_message = "Audit interval must be between 30 and 3600 seconds."
  }
}

# -----------------------------------------------------------------------------
# Notifications
# -----------------------------------------------------------------------------

variable "slack_webhook_url" {
  description = "Slack webhook URL for security alert notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
