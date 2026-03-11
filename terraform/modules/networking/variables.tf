###############################################################################
# Networking Module — Variables
###############################################################################

variable "environment" {
  description = "Environment name (e.g., prod, staging)"
  type        = string

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be one of: prod, staging, dev."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for subnet tagging)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "AZ count must be between 2 and 4."
  }
}

variable "subnet_newbits" {
  description = "Number of additional bits to add for subnet CIDR calculation"
  type        = number
  default     = 4

  validation {
    condition     = var.subnet_newbits >= 2 && var.subnet_newbits <= 8
    error_message = "Subnet newbits must be between 2 and 8."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet internet access"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost savings for non-production)"
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "VPC flow log retention period in days"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.flow_log_retention_days)
    error_message = "Retention must be a valid CloudWatch Logs retention value."
  }
}

variable "flow_log_aggregation_interval" {
  description = "Maximum aggregation interval for flow logs in seconds"
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.flow_log_aggregation_interval)
    error_message = "Aggregation interval must be 60 or 600 seconds."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
