###############################################################################
# DEV ENVIRONMENT — Terragrunt Entry Point
#
# WHAT THIS FILE DOES:
#   Tells Terragrunt: "I'm the dev environment. Inherit the root config,
#   use the same Terraform code as prod, but with these smaller values."
#
# HOW IT WORKS:
#   1. include "root" → Inherits remote state, provider config from root
#   2. terraform.source → Points to prod/main.tf as the Terraform code
#      (we REUSE prod's main.tf — it's parameterized via variables)
#   3. inputs → Override the variables with dev-appropriate values
#
# TO DEPLOY DEV:
#   cd terraform/environments/dev
#   terragrunt plan    # Preview what will be created
#   terragrunt apply   # Create the dev infrastructure
###############################################################################

# Inherit shared config (remote state, provider versions, etc.)
include "root" {
  path = find_in_parent_folders()
}

# Reuse the same Terraform root module as production
# The "//" tells Terragrunt "this is a Terraform source, not a file path"
terraform {
  source = "${dirname(find_in_parent_folders())}//environments/prod"
}

# ---------------------------------------------------------------------------
# DEV-SPECIFIC INPUTS
# These override the variables defined in prod/main.tf
#
# Cost optimization strategy for dev:
#   - Spot instances (can be interrupted, 70% cheaper)
#   - Fewer, smaller nodes
#   - Shorter log retention
#   - Fewer security tool replicas
#   - Public EKS endpoint (easier to debug from laptop)
# ---------------------------------------------------------------------------
inputs = {
  # --- Networking ---
  aws_region = "us-east-1"
  vpc_cidr   = "10.10.0.0/16"        # Different CIDR to avoid conflicts

  # --- EKS Cluster ---
  kubernetes_version  = "1.29"
  node_instance_types = ["t3.medium"] # Smaller instances = cheaper
  node_desired_size   = 1             # Just 1 node for dev
  node_min_size       = 1
  node_max_size       = 3

  # --- Monitoring ---
  grafana_admin_password = "dev-password-change-me" # Use secrets manager in real env
  enable_grafana_ingress = false

  # --- Alerts ---
  slack_webhook_url = ""              # Optional for dev
}
