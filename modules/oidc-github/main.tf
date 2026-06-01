# ##############################################################################
# GITHUB OIDC MODULE - lsd-payments
#
# Creates the trust relationship between your AWS account and GitHub.
# This is created once and referenced by the iam-roles module.
#
# Without this: GitHub Actions needs stored access keys to call AWS.
# With this: GitHub Actions gets temporary credentials by proving
# its identity through a signed token. No keys stored anywhere.
#
# The three fields explained:
#
# url - GitHub's OIDC identity endpoint.
#   AWS will verify incoming tokens against this URL.
#   Every GitHub Actions workflow gets tokens from here.
#
# client_id_list - the intended audience for tokens we will accept.
#   "sts.amazonaws.com" means we only accept tokens that were
#   issued specifically for AWS STS.
#   A token intended for another service cannot be used here.
#
# thumbprint_list - fingerprint of GitHub's SSL certificate.
#   AWS uses this to verify it is talking to the real GitHub endpoint.
#   This value is published by GitHub and is stable.
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

output "arn" {
  description = "ARN of the GitHub OIDC provider - passed to iam-roles module"
  value       = aws_iam_openid_connect_provider.github.arn
}
