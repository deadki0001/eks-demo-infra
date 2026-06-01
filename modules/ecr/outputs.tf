# ##############################################################################
# ECR OUTPUTS
#
# The repository URLs are what your CI pipeline uses to push images
# and what Kubernetes uses to pull them.
#
# A URL looks like:
# 988176743547.dkr.ecr.us-east-2.amazonaws.com/lsd-frontend
#
# Breaking that down:
#   988176743547          - your AWS account ID
#   dkr.ecr               - Docker registry service
#   us-east-2             - your region
#   amazonaws.com         - AWS domain
#   lsd-frontend          - your repository name
# ##############################################################################

output "frontend_repository_url" {
  description = "URL for pushing and pulling frontend images"
  value       = aws_ecr_repository.frontend.repository_url
}

output "backend_repository_url" {
  description = "URL for pushing and pulling backend images"
  value       = aws_ecr_repository.backend.repository_url
}
