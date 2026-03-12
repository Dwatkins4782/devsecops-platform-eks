###############################################################################
# PROD ENVIRONMENT — Terragrunt Entry Point
#
# WHAT THIS FILE DOES:
#   Tells Terragrunt: "I'm the prod environment. Inherit the root config,
#   use the Terraform code right here in this directory, with prod values."
#
# HOW IT WORKS:
#   1. include "root" → Inherits remote state, provider config from root
#   2. terraform.source → Points to "." (this directory contains main.tf)
#   3. inputs → Sets the variables with production-grade values
#
# TO DEPLOY PROD:
#   cd terraform/environments/prod
#   terragrunt plan    # Preview what will be created
#   terragrunt apply   # Create the production infrastructure
###############################################################################

# Inherit shared config (remote state, provider versions, etc.)
include "root" {
  path = find_in_parent_folders()
}

# Production uses the Terraform code in THIS directory (main.tf lives here)
terraform {
  source = "."
}

# ---------------------------------------------------------------------------
# PROD-SPECIFIC INPUTS
#
# Strategy: Maximum reliability and security
#   - Larger instance types for production workloads
#   - More nodes with higher min/max for resilience
#   - Longer log retention for compliance
#   - Full security tool deployment
#   - Private EKS endpoint only
# ---------------------------------------------------------------------------
inputs = {
  # --- Networking ---
  aws_region = "us-east-1"
  vpc_cidr   = "10.0.0.0/16"

  # --- EKS Cluster ---
  kubernetes_version  = "1.29"
  node_instance_types = ["t3.xlarge"]
  node_desired_size   = 3
  node_min_size       = 3
  node_max_size       = 10

  # --- Monitoring ---
  grafana_admin_password = "prod-password-change-me"  # Use secrets manager in real env
  enable_grafana_ingress = true

  # --- Alerts ---
  slack_webhook_url = ""  # Set via TF_VAR_slack_webhook_url in CI/CD
}
