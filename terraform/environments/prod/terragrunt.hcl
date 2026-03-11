###############################################################################
# Terragrunt Configuration — Production Environment
# Wraps the root Terraform module with remote state and provider config.
###############################################################################

# -----------------------------------------------------------------------------
# Remote State — S3 Backend with DynamoDB Locking
# -----------------------------------------------------------------------------

remote_state {
  backend = "s3"

  config = {
    bucket         = "devsecops-platform-terraform-state-prod"
    key            = "prod/eks-cluster/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "devsecops-platform-terraform-locks"

    s3_bucket_tags = {
      Name        = "devsecops-platform-terraform-state"
      Environment = "prod"
      ManagedBy   = "terragrunt"
    }

    dynamodb_table_tags = {
      Name        = "devsecops-platform-terraform-locks"
      Environment = "prod"
      ManagedBy   = "terragrunt"
    }
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# -----------------------------------------------------------------------------
# Terragrunt Settings
# -----------------------------------------------------------------------------

terraform {
  source = "."

  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()

    optional_var_files = [
      "${get_terragrunt_dir()}/terraform.tfvars",
      "${get_terragrunt_dir()}/secrets.tfvars",
    ]
  }

  extra_arguments "parallelism" {
    commands  = ["plan", "apply", "destroy"]
    arguments = ["-parallelism=20"]
  }

  before_hook "validate" {
    commands = ["plan", "apply"]
    execute  = ["terraform", "validate"]
  }
}

# -----------------------------------------------------------------------------
# Input Variables
# -----------------------------------------------------------------------------

inputs = {
  aws_region          = "us-east-1"
  kubernetes_version  = "1.29"
  vpc_cidr            = "10.0.0.0/16"
  node_instance_types = ["t3.xlarge"]
  node_desired_size   = 3
  node_min_size       = 3
  node_max_size       = 10
}

# -----------------------------------------------------------------------------
# Generate Provider Versions Lock
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Retry Configuration
# -----------------------------------------------------------------------------

retry_max_attempts       = 3
retry_sleep_interval_sec = 30
