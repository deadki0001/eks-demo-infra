# ##############################################################################
# IAM ROLES MODULE - lsd-payments
#
# This module creates all IAM roles used by the project.
# No static access keys are created anywhere.
# Everything uses role assumption via OIDC.
#
# What gets created:
#   1 ALB Controller role     (assumed by ALB controller pod via IRSA)
#   1 External Secrets role   (assumed by External Secrets pod via IRSA)
#   1 GitHub Actions role     (assumed by CI pipeline via GitHub OIDC)
# ##############################################################################


# ##############################################################################
# LOCAL VALUES
#
# The OIDC provider URL looks like:
# https://oidc.eks.us-east-2.amazonaws.com/id/ABC123
#
# IAM trust policies need the URL without the https:// prefix.
# local.oidc_issuer strips that prefix so we do not have to
# repeat the replace() call in every trust policy below.
# ##############################################################################

locals {
  oidc_issuer = replace(var.oidc_provider_url, "https://", "")
}


# ##############################################################################
# ALB CONTROLLER ROLE
#
# The AWS Load Balancer Controller runs as a pod inside your cluster.
# When you create a Kubernetes Ingress resource, this controller
# reads it and creates a real AWS Application Load Balancer for you.
#
# To create that ALB it needs AWS permissions - specifically the ability
# to create and manage load balancers, target groups, listeners, and
# security groups.
#
# The trust policy below says:
# "Only allow assumption of this role if the request comes from
#  a pod using the service account named aws-load-balancer-controller
#  in the kube-system namespace of our specific EKS cluster."
#
# Breaking down the trust policy conditions:
#
# StringEquals on :sub means the subject must exactly match.
# The subject for a Kubernetes service account always follows this format:
# system:serviceaccount:<namespace>:<service-account-name>
#
# StringEquals on :aud means the audience must be sts.amazonaws.com
# This confirms the token is intended for AWS, not some other service.
# ##############################################################################

resource "aws_iam_role" "alb_controller" {
  name        = "lsd-payments-dev-alb-controller"
  description = "Assumed by ALB Controller pod to manage AWS load balancers"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "lsd-payments-dev-alb-controller"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# The ALB controller needs a large set of permissions to manage load balancers.
# Rather than writing them all by hand AWS provides the official policy document.
# We downloaded it earlier to modules/iam-roles/policies/alb-controller.json
# file() reads the contents of that file and uses it as the policy.

resource "aws_iam_role_policy" "alb_controller" {
  name   = "alb-controller-policy"
  role   = aws_iam_role.alb_controller.id
  policy = file("${path.module}/policies/alb-controller.json")
}


# ##############################################################################
# EXTERNAL SECRETS ROLE
#
# External Secrets Operator runs as a pod and watches for ExternalSecret
# resources in your cluster. When it finds one it calls AWS Secrets Manager,
# retrieves the secret value, and creates a native Kubernetes Secret.
#
# This is how your backend pod gets the database password without it
# ever being hardcoded anywhere. The flow is:
#
# 1. Terraform stores DB password in Secrets Manager
# 2. External Secrets Operator reads it using this role
# 3. Creates a Kubernetes Secret in the eks-demo namespace
# 4. Backend pod mounts that Kubernetes Secret as environment variables
#
# The trust policy locks this role to only the external-secrets
# service account in the external-secrets namespace.
# ##############################################################################

resource "aws_iam_role" "external_secrets" {
  name        = "lsd-payments-dev-external-secrets"
  description = "Assumed by External Secrets Operator to read from Secrets Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer}:sub" = "system:serviceaccount:external-secrets:external-secrets-sa"
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "lsd-payments-dev-external-secrets"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# This role only needs two permissions:
# GetSecretValue  - read the actual secret value
# DescribeSecret  - read metadata about the secret (name, ARN, rotation status)
#
# The Resource line restricts it to only secrets that start with
# "lsd-payments/" in your account and region.
# It cannot read any other secrets in your account.

resource "aws_iam_role_policy" "external_secrets" {
  name = "external-secrets-policy"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:lsd-payments/*"
      }
    ]
  })
}


# ##############################################################################
# GITHUB ACTIONS DEPLOY ROLE
#
# This role is assumed by your GitHub Actions CI pipeline.
# It gives the pipeline permission to push images to ECR and
# describe the EKS cluster to update kubeconfig.
#
# The trust policy here is different from the IRSA roles above.
# Instead of trusting your EKS cluster's OIDC provider it trusts
# GitHub's OIDC provider at token.actions.githubusercontent.com
#
# When a GitHub Actions workflow runs, GitHub issues it a short-lived
# JWT token. That token contains claims about where it came from:
# - which organisation
# - which repository
# - which branch or environment
#
# The condition StringLike on :sub matches that claim.
# "repo:deadki0001/eks-demo-app:*" means:
# only tokens from the eks-demo-app repo in the deadki0001 account.
# The * at the end matches any branch or ref.
#
# No access keys are stored in GitHub secrets.
# The pipeline just assumes this role and gets temporary credentials.
# ##############################################################################

resource "aws_iam_role" "github_actions" {
  name        = "lsd-payments-dev-github-actions-deploy"
  description = "Assumed by GitHub Actions to push images and deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_app_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "lsd-payments-dev-github-actions-deploy"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# Three permissions for GitHub Actions:
#
# ecr:GetAuthorizationToken - get a login token for ECR
#   This is how docker login works against ECR.
#   Resource * is required here - this API does not support
#   restricting to specific repositories.
#
# ECR image push permissions - scoped to only your two repos.
#   BatchCheckLayerAvailability - check if layers already exist before upload
#   InitiateLayerUpload         - start uploading an image layer
#   UploadLayerPart             - upload a chunk of the layer
#   CompleteLayerUpload         - finish the layer upload
#   PutImage                    - write the final image manifest
#   DescribeImages              - verify the image exists after push
#
# eks:DescribeCluster - read cluster details to build kubeconfig.
#   The pipeline needs this to run kubectl commands against the cluster.

resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:${var.region}:${var.account_id}:repository/lsd-frontend",
          "arn:aws:ecr:${var.region}:${var.account_id}:repository/lsd-backend"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.region}:${var.account_id}:cluster/lsd-payments-dev"
      }
    ]
  })
}
