# ##############################################################################
# BOOTSTRAP - One time only
#
# This is the only thing deployed manually.
# Everything else is created by the GitHub Actions pipeline.
#
# Why this must be manual:
# The pipeline assumes an IAM role to run Terraform.
# That role's trust policy says "trust tokens from GitHub OIDC provider".
# The GitHub OIDC provider must exist in AWS before that trust policy works.
# So we create the provider first, then the pipeline creates the role.
#
# Run once:
#   terraform init
#   terraform apply
#   Never run again.
# ##############################################################################

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = "us-east-2"
}

# ##############################################################################
# GITHUB OIDC PROVIDER
#
# Creates the trust relationship between AWS and GitHub Actions.
# Once this exists the pipeline can assume IAM roles without stored keys.
# ##############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name        = "github-actions-oidc-provider"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "github_oidc_provider_arn" {
  description = "Add this to your GitHub Actions secrets as GITHUB_OIDC_PROVIDER_ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}
