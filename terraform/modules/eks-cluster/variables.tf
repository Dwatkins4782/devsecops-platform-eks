###############################################################################
# EKS Cluster Module — Variables
###############################################################################

# -----------------------------------------------------------------------------
# Cluster Configuration
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,99}$", var.cluster_name))
    error_message = "Cluster name must start with a letter, contain only alphanumerics and hyphens, and be 2-100 characters."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"

  validation {
    condition     = can(regex("^1\\.(2[7-9]|3[0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.27 or later."
  }
}

variable "enable_public_endpoint" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.public_access_cidrs : can(cidrnetmask(cidr))])
    error_message = "All entries must be valid CIDR blocks."
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-f0-9]{8,17}$", var.vpc_id))
    error_message = "VPC ID must be a valid AWS VPC identifier."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster and node groups"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for high availability."
  }
}

# -----------------------------------------------------------------------------
# Node Group Configuration
# -----------------------------------------------------------------------------

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.xlarge"]
}

variable "node_capacity_type" {
  description = "Capacity type for nodes: ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "Capacity type must be ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_desired_size >= 1 && var.node_desired_size <= 100
    error_message = "Desired size must be between 1 and 100."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes for autoscaling"
  type        = number
  default     = 3

  validation {
    condition     = var.node_min_size >= 1
    error_message = "Minimum node size must be at least 1."
  }
}

variable "node_max_size" {
  description = "Maximum number of worker nodes for autoscaling"
  type        = number
  default     = 10

  validation {
    condition     = var.node_max_size >= 1 && var.node_max_size <= 100
    error_message = "Maximum node size must be between 1 and 100."
  }
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 50

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 1000
    error_message = "Disk size must be between 20 and 1000 GB."
  }
}

variable "node_labels" {
  description = "Kubernetes labels to apply to nodes"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention value."
  }
}

# -----------------------------------------------------------------------------
# Add-on Versions
# -----------------------------------------------------------------------------

variable "calico_version" {
  description = "Calico Helm chart version"
  type        = string
  default     = "3.27.2"
}

variable "vpc_cni_addon_version" {
  description = "VPC CNI add-on version"
  type        = string
  default     = "v1.16.4-eksbuild.2"
}

variable "coredns_addon_version" {
  description = "CoreDNS add-on version"
  type        = string
  default     = "v1.11.1-eksbuild.6"
}

variable "kube_proxy_addon_version" {
  description = "kube-proxy add-on version"
  type        = string
  default     = "v1.29.1-eksbuild.2"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
