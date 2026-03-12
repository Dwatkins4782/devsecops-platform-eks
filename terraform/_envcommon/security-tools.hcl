###############################################################################
# SHARED MODULE CONFIG: Security Tools (Falco + Trivy + OPA Gatekeeper)
#
# Depends on EKS cluster because security tools are deployed INTO the cluster.
###############################################################################

terraform {
  source = "${dirname(find_in_parent_folders())}//modules/security-tools"
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name = "devsecops-mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}
