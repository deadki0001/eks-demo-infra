# ─────────────────────────────────────────────────────────────────────────────
# VPC OUTPUTS
#
# These are the values other modules need from the VPC.
# The EKS module needs subnet IDs to know where to put nodes.
# The RDS module needs subnet IDs to know where to put the database.
# The IAM module needs the VPC ID for security group rules.
#
# Think of outputs as the module handing you a piece of paper
# with the IDs of everything it just created.
# ─────────────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "The ID of the VPC - used by security groups and RDS"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs - used by the load balancer"
  value = [
    aws_subnet.public_az1.id,
    aws_subnet.public_az2.id,
    aws_subnet.public_az3.id
  ]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs - used by EKS nodes and RDS"
  value = [
    aws_subnet.private_az1.id,
    aws_subnet.private_az2.id,
    aws_subnet.private_az3.id
  ]
}
