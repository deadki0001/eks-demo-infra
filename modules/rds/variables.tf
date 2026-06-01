variable "vpc_id" {
  description = "VPC ID - from vpc module output"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs - from vpc module output"
  type        = list(string)
}

variable "eks_node_sg_id" {
  description = "EKS node security group ID - from eks module output"
  type        = string
}

variable "db_password" {
  description = "Database password - from random_password resource"
  type        = string
  sensitive   = true
}
