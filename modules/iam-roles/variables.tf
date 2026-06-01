# ##############################################################################
# IAM ROLES VARIABLES
#
# These values cannot be hardcoded because they are only known after
# other resources are created.
#
# oidc_provider_arn and oidc_provider_url come from the EKS module.
# They are unique to your cluster and only exist after the cluster is created.
#
# github_oidc_provider_arn comes from the oidc-github module.
# It is created once and reused across all roles that GitHub needs.
#
# account_id and region are used to build ARNs in the policy documents.
# ##############################################################################

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider - from eks module output"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS cluster OIDC provider - from eks module output"
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider - from oidc-github module output"
  type        = string
}

variable "github_org" {
  description = "GitHub username or org name - used in trust policy"
  type        = string
}

variable "github_app_repo" {
  description = "GitHub app repo name - used in trust policy"
  type        = string
}

variable "region" {
  description = "AWS region - used to build ARNs"
  type        = string
}

variable "account_id" {
  description = "AWS account ID - used to build ARNs"
  type        = string
}
