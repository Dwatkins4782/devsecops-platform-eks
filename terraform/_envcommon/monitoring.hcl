###############################################################################
# SHARED MODULE CONFIG: Monitoring (Prometheus + Grafana)
#
# Depends on EKS cluster because it needs the OIDC provider for
# IAM Roles for Service Accounts (IRSA).
###############################################################################

terraform {
  source = "${dirname(find_in_parent_folders())}//modules/monitoring"
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name      = "devsecops-mock-cluster"
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/mock"
    oidc_provider_url = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  cluster_name      = dependency.eks_cluster.outputs.cluster_name
  oidc_provider_arn = dependency.eks_cluster.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks_cluster.outputs.oidc_provider_url
}
