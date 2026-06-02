# The only variable this module needs from outside is the subnet IDs.
# Everything else is hardcoded for clarity.
# The subnet IDs come from the VPC module output.

variable "private_subnet_ids" {
  description = "List of private subnet IDs where nodes will run"
  type        = list(string)
}

variable "sso_admin_role_arn" {
  description = "ARN of the SSO admin role - granted cluster admin access automatically"
  type        = string
}
