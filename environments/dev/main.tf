# ##############################################################################
# DEV ENVIRONMENT - lsd-payments
#
# This is the root file that ties all modules together.
# Think of it as the conductor - it does not contain logic itself,
# it calls each module and passes outputs from one into another.
#
# Dependency order:
#   oidc-github  (no dependencies)
#       |
#      vpc       (no dependencies)
#       |
#      ecr       (no dependencies)
#       |
#      eks       (needs vpc private_subnet_ids)
#       |
#   iam-roles    (needs eks oidc outputs + github oidc arn)
#       |
#      rds       (needs vpc and eks outputs)
#       |
#   secrets      (needs rds endpoint)
#       |
#   aws-auth     (needs eks and iam-roles outputs)
# ##############################################################################

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}


# ##############################################################################
# PROVIDERS
#
# AWS provider picks up credentials from AWS_PROFILE environment variable.
# That is your SSO session - no keys needed.
#
# Kubernetes provider connects to the cluster using a fresh token
# fetched by the AWS CLI each time it is needed.
# Same mechanism as kubectl - just automated.
# ##############################################################################

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name", var.cluster_name,
      "--region", var.aws_region
    ]
  }
}


# ##############################################################################
# RANDOM PASSWORD
#
# Generates a 24 character password for RDS.
# special = false avoids characters like $ and @ that cause
# issues in connection strings and shell commands.
#
# This password is passed to the RDS module and stored in
# Secrets Manager. It never appears in application code.
# ##############################################################################

resource "random_password" "db" {
  length  = 24
  special = false
}


# ##############################################################################
# MODULE: GITHUB OIDC PROVIDER
# Creates the trust between AWS and GitHub Actions.
# No inputs needed - GitHub's endpoint is a known public URL.
# Output: arn - passed to iam-roles module
# ##############################################################################


# ##############################################################################
# MODULE: VPC
# Creates the network foundation.
# No inputs needed - CIDRs and AZs are hardcoded in the module.
# Outputs: vpc_id, public_subnet_ids, private_subnet_ids
# ##############################################################################

module "vpc" {
  source = "../../modules/vpc"
}


# ##############################################################################
# MODULE: ECR
# Creates the container image repositories.
# No inputs needed - repo names are hardcoded in the module.
# Outputs: frontend_repository_url, backend_repository_url
# ##############################################################################

module "ecr" {
  source = "../../modules/ecr"
}


# ##############################################################################
# MODULE: EKS
# Creates the Kubernetes cluster and worker nodes.
# Needs private subnet IDs so nodes are placed in private subnets.
# Outputs: cluster_name, cluster_endpoint, cluster_ca,
#          node_role_arn, oidc_provider_arn, oidc_provider_url,
#          node_security_group_id
# ##############################################################################

module "eks" {
  source             = "../../modules/eks"
  private_subnet_ids = module.vpc.private_subnet_ids
  sso_admin_role_arn = "arn:aws:iam::988176743547:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_AdministratorAccess_d45f6785e0e6d083"
}


# ##############################################################################
# MODULE: IAM ROLES
# Creates IRSA roles and the GitHub Actions deploy role.
# Needs EKS OIDC outputs to build trust policies scoped to this cluster.
# Needs GitHub OIDC ARN to build the GitHub Actions trust policy.
# Outputs: alb_controller_role_arn, external_secrets_role_arn,
#          github_actions_role_arn
# ##############################################################################

module "iam_roles" {
  source = "../../modules/iam-roles"

  oidc_provider_arn        = module.eks.oidc_provider_arn
  oidc_provider_url        = module.eks.oidc_provider_url
  github_oidc_provider_arn = "arn:aws:iam::988176743547:oidc-provider/token.actions.githubusercontent.com"
  github_org               = var.github_org
  github_app_repo          = var.github_app_repo
  region                   = var.aws_region
  account_id               = var.aws_account_id
}


# ##############################################################################
# MODULE: RDS
# Creates the PostgreSQL database in private subnets.
# Needs vpc_id and private_subnet_ids for placement.
# Needs eks_node_sg_id so only EKS nodes can connect on port 5432.
# Needs db_password from the random_password resource above.
# Outputs: endpoint, port
# ##############################################################################

module "rds" {
  source             = "../../modules/rds"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  sso_admin_role_arn = "arn:aws:iam::988176743547:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_AdministratorAccess_d45f6785e0e6d083"
  eks_node_sg_id     = module.eks.node_security_group_id
  db_password        = random_password.db.result
}


# ##############################################################################
# SECRETS MANAGER - DATABASE CREDENTIALS
#
# Stores all RDS connection details as a single JSON secret.
# External Secrets Operator reads this secret and creates a
# Kubernetes Secret in the cluster namespace.
# The backend pod reads that Kubernetes Secret as environment variables.
#
# The flow:
# Terraform -> Secrets Manager -> External Secrets -> K8s Secret -> Pod
# ##############################################################################

resource "aws_secretsmanager_secret" "rds" {
  name        = "lsd-payments/rds-v2"
  description = "RDS connection details for lsd-payments backend"

  tags = {
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  secret_string = jsonencode({
    host     = module.rds.endpoint
    port     = "5432"
    username = "lsdadmin"
    password = random_password.db.result
    dbname   = "lsdpayments"
  })
}


# ##############################################################################
# AWS AUTH CONFIGMAP
#
# Maps IAM roles to Kubernetes RBAC groups.
# Three entries:
#
# 1. Node role - required or nodes cannot join the cluster
# 2. GitHub Actions role - allows CI pipeline to run kubectl
# 3. Your SSO admin role - your personal cluster admin access
#
# The SSO role ARN comes from your sts get-caller-identity output.
# It is the assumed-role ARN without the session name at the end.
# Example:
#   Full ARN:  arn:aws:sts::988176743547:assumed-role/AWSReservedSSO_.../deadkithedeveloper
#   Role ARN:  arn:aws:iam::988176743547:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_...
#
# Note the difference:
#   sts:assumed-role -> what you see in get-caller-identity
#   iam:role         -> what goes in aws-auth
# ##############################################################################

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  force = true

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = module.eks.node_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = module.iam_roles.github_actions_role_arn
        username = "github-actions"
        groups   = ["lsd-deployers"]
      },
      {
        rolearn  = "arn:aws:iam::${var.aws_account_id}:role/aws-reserved/sso.amazonaws.com/us-east-2/AWSReservedSSO_AdministratorAccess_d45f6785e0e6d083"
        username = "eks-admin"
        groups   = ["system:masters"]
      }
    ])
  }

  depends_on = [module.eks]
}


# ##############################################################################
# RBAC - DEPLOYERS GROUP
#
# Binds the lsd-deployers group to the built-in edit ClusterRole.
# edit allows: create/update deployments, services, configmaps, pods
# edit blocks:  modify RBAC, nodes, persistent volumes, cluster settings
#
# GitHub Actions gets this group - enough to deploy, not enough
# to escalate privileges or modify security controls.
# ##############################################################################

resource "kubernetes_cluster_role_binding" "deployers" {
  metadata {
    name = "lsd-deployers"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "Group"
    name      = "lsd-deployers"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [module.eks]
}
