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

# ##############################################################################
# GITHUB ACTIONS IAM ROLE
#
# This role is assumed by the GitHub Actions pipeline to run Terraform.
# It needs broad permissions to create VPC, EKS, RDS, IAM roles etc.
# We create it manually once so the pipeline can use it immediately.
#
# The trust policy locks it to only your specific infra repo.
# No other repo can assume this role.
# ##############################################################################

resource "aws_iam_role" "github_actions_infra" {
  name        = "lsd-payments-github-actions-infra"
  description = "Assumed by GitHub Actions to run Terraform for infrastructure"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:deadki0001/eks-demo-infra:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "lsd-payments-github-actions-infra"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# ##############################################################################
# PERMISSIONS FOR THE INFRA ROLE
#
# This role needs to create and manage all infrastructure resources.
# We attach AdministratorAccess for the demo - in production you would
# scope this down to only the services Terraform needs.
# ##############################################################################

resource "aws_iam_role_policy_attachment" "github_actions_infra" {
  role       = aws_iam_role.github_actions_infra.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_actions_infra_role_arn" {
  description = "Add this to GitHub secrets as AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions_infra.arn
}
