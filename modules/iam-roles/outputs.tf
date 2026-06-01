# ##############################################################################
# IAM ROLES OUTPUTS
#
# These ARNs are needed in two places:
#
# alb_controller_role_arn   - passed to helm install for the ALB controller
#                             so the controller's service account gets annotated
#                             with the role ARN
#
# external_secrets_role_arn - same pattern for External Secrets Operator
#
# github_actions_role_arn   - goes into the aws-auth ConfigMap in environments/dev/main.tf
#                             so GitHub Actions can authenticate to the cluster
# ##############################################################################

output "alb_controller_role_arn" {
  description = "Role ARN for ALB Controller - used in helm install command"
  value       = aws_iam_role.alb_controller.arn
}

output "external_secrets_role_arn" {
  description = "Role ARN for External Secrets Operator - used in helm install command"
  value       = aws_iam_role.external_secrets.arn
}

output "github_actions_role_arn" {
  description = "Role ARN for GitHub Actions - goes into aws-auth ConfigMap"
  value       = aws_iam_role.github_actions.arn
}
