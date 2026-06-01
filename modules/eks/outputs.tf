# ─────────────────────────────────────────────────────────────────────────────
# EKS OUTPUTS
#
# cluster_name     - used by kubectl and helm commands
# cluster_endpoint - the URL kubectl connects to
# cluster_ca       - the certificate kubectl uses to verify the connection
# node_role_arn    - goes into aws-auth ConfigMap so nodes can join
# oidc_provider_arn - used by IAM roles module to create IRSA roles
# oidc_provider_url - used by IAM roles module to build trust policies
# node_security_group_id - used by RDS to allow traffic from nodes only
# ─────────────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca" {
  description = "Base64 encoded certificate for kubectl"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_role_arn" {
  description = "ARN of the node IAM role - needed in aws-auth ConfigMap"
  value       = aws_iam_role.node.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider - used to create IRSA roles"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider - used in IAM trust policies"
  value       = aws_iam_openid_connect_provider.cluster.url
}

output "node_security_group_id" {
  description = "Security group ID of the nodes - used by RDS to allow access"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
