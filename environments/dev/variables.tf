variable "aws_account_id" {
  description = "Your AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "lsd-payments-dev"
}

variable "github_org" {
  description = "Your GitHub username"
  type        = string
}

variable "github_app_repo" {
  description = "Name of your app repo"
  type        = string
  default     = "eks-demo-app"
}
