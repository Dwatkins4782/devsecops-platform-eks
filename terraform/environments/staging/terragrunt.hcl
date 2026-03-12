###############################################################################
# STAGING ENVIRONMENT — Terragrunt Entry Point
#
# Staging is the "pre-production" environment. It mirrors production
# as closely as possible but with slightly reduced resources.
# Code must pass staging before going to production.
###############################################################################

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${dirname(find_in_parent_folders())}//environments/prod"
}

# ---------------------------------------------------------------------------
# STAGING-SPECIFIC INPUTS
#
# Strategy: Close to production but not as expensive
#   - Same instance type family but one size down
#   - Fewer nodes
#   - Moderate log retention
# ---------------------------------------------------------------------------
inputs = {
  # --- Networking ---
  aws_region = "us-east-1"
  vpc_cidr   = "10.20.0.0/16"

  # --- EKS Cluster ---
  kubernetes_version  = "1.29"
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  node_min_size       = 2
  node_max_size       = 5

  # --- Monitoring ---
  grafana_admin_password = "staging-password-change-me"
  enable_grafana_ingress = false

  # --- Alerts ---
  slack_webhook_url = ""
}
