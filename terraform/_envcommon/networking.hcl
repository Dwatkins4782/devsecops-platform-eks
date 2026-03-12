###############################################################################
# SHARED MODULE CONFIG: Networking
#
# WHAT THIS FILE DOES:
#   Defines the common configuration for the networking Terraform module.
#   Every environment's networking/terragrunt.hcl includes this file
#   to get the module source path and default inputs.
#
# HOW IT'S USED:
#   In environments/dev/terragrunt.hcl:
#     include "envcommon" {
#       path = "${dirname(find_in_parent_folders())}/_envcommon/networking.hcl"
#     }
#   This gives the dev environment all the defaults defined here,
#   then dev can override specific values in its own inputs block.
###############################################################################

terraform {
  # Point to the shared networking module
  # dirname(find_in_parent_folders()) resolves to the terraform/ directory
  source = "${dirname(find_in_parent_folders())}//modules/networking"
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment
}

# Default inputs shared across all environments
inputs = {
  environment  = local.environment
  cluster_name = "devsecops-${local.environment}-cluster"
}
