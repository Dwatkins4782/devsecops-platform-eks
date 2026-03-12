###############################################################################
# DEV ENVIRONMENT VARIABLES
#
# This file defines variables specific to the dev environment.
# The root terragrunt.hcl reads this file to know which environment
# it's deploying to, which AWS region to use, etc.
###############################################################################

locals {
  environment = "dev"
  aws_region  = "us-east-1"
  account_id  = "123456789012"  # Replace with your actual AWS account ID
}
