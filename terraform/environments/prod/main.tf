###############################################################################
# Production Environment — Root Module
# Composes all infrastructure modules for the production EKS cluster.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_eks_cluster" "main" {
  name = module.eks_cluster.cluster_name

  depends_on = [module.eks_cluster]
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks_cluster.cluster_name

  depends_on = [module.eks_cluster]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  environment  = "prod"
  cluster_name = "devsecops-${local.environment}-cluster"
  project      = "devsecops-platform"

  common_tags = {
    Environment = local.environment
    Project     = local.project
    ManagedBy   = "terraform"
    Owner       = "platform-engineering"
    CostCenter  = "infrastructure"
  }
}

# -----------------------------------------------------------------------------
# Networking Module
# -----------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  environment    = local.environment
  cluster_name   = local.cluster_name
  vpc_cidr       = var.vpc_cidr
  az_count       = 3

  enable_nat_gateway = true
  single_nat_gateway = false

  flow_log_retention_days       = 90
  flow_log_aggregation_interval = 60

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EKS Cluster Module
# -----------------------------------------------------------------------------

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  enable_public_endpoint = false

  node_instance_types = var.node_instance_types
  node_capacity_type  = "ON_DEMAND"
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = 100

  kms_deletion_window = 30
  log_retention_days  = 90

  tags = local.common_tags

  depends_on = [module.networking]
}

# -----------------------------------------------------------------------------
# Monitoring Module
# -----------------------------------------------------------------------------

module "monitoring" {
  source = "../../modules/monitoring"

  cluster_name      = local.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_provider_url = module.eks_cluster.oidc_provider_url

  prometheus_replicas     = 2
  prometheus_retention    = "15d"
  prometheus_storage_size = "50Gi"

  alertmanager_replicas = 2

  grafana_admin_password  = var.grafana_admin_password
  grafana_ingress_enabled = var.enable_grafana_ingress
  grafana_ingress_hosts   = var.grafana_ingress_hosts
  grafana_certificate_arn = var.grafana_certificate_arn

  slack_webhook_url      = var.slack_webhook_url
  slack_critical_channel = "#alerts-prod-critical"
  slack_warning_channel  = "#alerts-prod-warning"

  storage_class_name = "gp3"

  tags = local.common_tags

  depends_on = [module.eks_cluster]
}

# -----------------------------------------------------------------------------
# Security Tools Module
# -----------------------------------------------------------------------------

module "security_tools" {
  source = "../../modules/security-tools"

  falco_driver_kind       = "modern_ebpf"
  falco_minimum_priority  = "notice"
  enable_falcosidekick    = true
  enable_falcosidekick_ui = true
  falco_slack_channel     = "#security-alerts-prod"

  trivy_severity_levels  = "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL"
  trivy_ignore_unfixed   = false
  trivy_concurrent_scans = 10
  trivy_compliance_cron  = "0 1 * * *"

  gatekeeper_replicas      = 3
  gatekeeper_audit_interval = 60

  slack_webhook_url = var.slack_webhook_url

  tags = local.common_tags

  depends_on = [module.eks_cluster]
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for the production environment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)
  default     = ["t3.xlarge"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "enable_grafana_ingress" {
  description = "Enable Grafana ingress"
  type        = bool
  default     = false
}

variable "grafana_ingress_hosts" {
  description = "Grafana ingress hostnames"
  type        = list(string)
  default     = []
}

variable "grafana_certificate_arn" {
  description = "ACM certificate ARN for Grafana"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook for alert notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_cluster.cluster_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks_cluster.oidc_provider_arn
}

output "grafana_service" {
  description = "Grafana service name"
  value       = module.monitoring.grafana_service_name
}
