output "cluster_name" {
  description = "Use this in: aws eks update-kubeconfig --name <value>"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server URL"
  value       = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  description = "Database hostname - already stored in Secrets Manager"
  value       = module.rds.endpoint
}

output "ecr_frontend_url" {
  description = "Use this in your CI pipeline to push frontend images"
  value       = module.ecr.frontend_repository_url
}

output "ecr_backend_url" {
  description = "Use this in your CI pipeline to push backend images"
  value       = module.ecr.backend_repository_url
}

output "alb_controller_role_arn" {
  description = "Use this in: helm install aws-load-balancer-controller"
  value       = module.iam_roles.alb_controller_role_arn
}

output "external_secrets_role_arn" {
  description = "Use this in: helm install external-secrets"
  value       = module.iam_roles.external_secrets_role_arn
}

output "github_actions_role_arn" {
  description = "Add this to your GitHub Actions secrets as AWS_ROLE_ARN"
  value       = module.iam_roles.github_actions_role_arn
}
