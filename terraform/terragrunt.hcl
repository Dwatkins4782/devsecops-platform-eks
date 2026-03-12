###############################################################################
# ROOT TERRAGRUNT CONFIGURATION
#
# WHAT THIS FILE DOES:
#   This is the "parent" config that ALL environments inherit from.
#   It defines shared settings that are the same everywhere:
#     - Where to store Terraform state (S3 bucket)
#     - Which provider versions to use
#     - How to configure the AWS provider
#
# HOW INHERITANCE WORKS:
#   Every environment's terragrunt.hcl has this line:
#     include "root" { path = find_in_parent_folders() }
#   That tells Terragrunt to "walk up the directory tree until you
#   find a terragrunt.hcl" — which is THIS file.
#
# DIRECTORY HIERARCHY:
#   terraform/
#   ├── terragrunt.hcl          ← YOU ARE HERE (root config)
#   ├── _envcommon/              ← Shared module configs
#   └── environments/
#       ├── dev/
#       │   ├── env.hcl          ← Dev-specific variables
#       │   └── terragrunt.hcl   ← Includes this root + overrides
#       ├── staging/
#       │   ├── env.hcl
#       │   └── terragrunt.hcl
#       └── prod/
#           ├── env.hcl
#           └── terragrunt.hcl
###############################################################################

# =============================================================================
# LOCALS: Read environment-specific variables from env.hcl
#
# read_terragrunt_config() reads the env.hcl file in the calling
# environment's directory. find_in_parent_folders("env.hcl") walks
# up from the calling directory to find env.hcl.
#
# Example: When called from environments/dev/terragrunt.hcl,
#          it finds environments/dev/env.hcl
# =============================================================================
locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_vars.locals.environment
  aws_region  = local.env_vars.locals.aws_region
  account_id  = local.env_vars.locals.account_id
}

# =============================================================================
# REMOTE STATE: Where Terraform stores its state file
#
# Each environment gets its OWN S3 bucket (devsecops-tfstate-dev,
# devsecops-tfstate-staging, devsecops-tfstate-prod) so they can
# never accidentally overwrite each other's state.
#
# The DynamoDB table provides LOCKING — it prevents two people from
# running `terraform apply` at the same time (which would corrupt state).
# =============================================================================
remote_state {
  backend = "s3"

  config = {
    # Each environment gets its own bucket
    bucket = "devsecops-tfstate-${local.environment}"

    # path_relative_to_include() auto-generates a unique key based on
    # the calling directory. Example:
    #   Called from environments/dev/ → key = "environments/dev/terraform.tfstate"
    #   Called from environments/prod/ → key = "environments/prod/terraform.tfstate"
    key = "${path_relative_to_include()}/terraform.tfstate"

    region  = local.aws_region
    encrypt = true

    # DynamoDB table for state locking (shared across environments)
    dynamodb_table = "devsecops-terraform-locks"

    # Tags for the auto-created S3 bucket
    s3_bucket_tags = {
      Name        = "devsecops-tfstate-${local.environment}"
      Environment = local.environment
      ManagedBy   = "terragrunt"
    }
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# =============================================================================
# GENERATE: Provider Version Locking
#
# This auto-generates a versions_override.tf file in each environment
# directory, ensuring all environments use the same provider versions.
# =============================================================================
generate "versions" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
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
    }
  EOF
}

# =============================================================================
# TERRAFORM SETTINGS: Extra arguments and hooks
# =============================================================================
terraform {
  # Run up to 20 resource operations in parallel (faster deploys)
  extra_arguments "parallelism" {
    commands  = ["plan", "apply", "destroy"]
    arguments = ["-parallelism=20"]
  }

  # Always validate before planning or applying
  before_hook "validate" {
    commands = ["plan", "apply"]
    execute  = ["terraform", "validate"]
  }
}

# =============================================================================
# RETRY: Automatically retry on transient failures
# (e.g., AWS rate limiting, network timeouts)
# =============================================================================
retry_max_attempts       = 3
retry_sleep_interval_sec = 30
