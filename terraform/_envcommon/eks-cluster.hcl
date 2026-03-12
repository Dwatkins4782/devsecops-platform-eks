###############################################################################
# SHARED MODULE CONFIG: EKS Cluster
#
# WHAT THIS FILE DOES:
#   Common config for the EKS cluster module. Includes a DEPENDENCY on
#   the networking module because EKS needs VPC ID and subnet IDs.
#
# DEPENDENCY EXPLAINED:
#   Terragrunt's "dependency" block tells it:
#   "Before you can plan/apply EKS, go plan/apply networking first,
#    then pass networking's outputs as inputs to EKS."
###############################################################################

terraform {
  source = "${dirname(find_in_parent_folders())}//modules/eks-cluster"
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment
}

# ---------------------------------------------------------------------------
# DEPENDENCY: EKS needs outputs from the networking module
# config_path is RELATIVE to the environment directory
# ---------------------------------------------------------------------------
dependency "networking" {
  config_path = "../networking"

  # Mock outputs for `terragrunt validate` when networking hasn't been applied yet
  mock_outputs = {
    vpc_id             = "vpc-mock-12345"
    private_subnet_ids = ["subnet-mock-1", "subnet-mock-2", "subnet-mock-3"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  cluster_name       = "devsecops-${local.environment}-cluster"
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnet_ids
}
