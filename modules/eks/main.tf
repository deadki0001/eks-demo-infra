# #############################################################################
# EKS MODULE - lsd-payments
#
# This file creates the Kubernetes cluster and everything it needs to run.
#
# What gets created:
#   1 EKS cluster          (the control plane - managed by AWS)
#   1 cluster IAM role     (permissions for EKS to call AWS APIs)
#   1 OIDC provider        (enables pods to assume IAM roles without keys)
#   1 node IAM role        (permissions for EC2 nodes)
#   1 launch template      (node config - enforces IMDSv2)
#   1 managed node group   (the actual EC2 worker nodes)
#   4 EKS add-ons          (vpc-cni, coredns, kube-proxy, ebs-csi)
# #############################################################################


# ## CLUSTER IAM ROLE #########################################################
# EKS needs an IAM role so it can make AWS API calls on your behalf.
# For example: creating load balancers, writing logs to CloudWatch,
# describing EC2 instances to track node health.
#
# The assume_role_policy answers the question:
# "who is allowed to USE this role?"
# In this case the answer is: the EKS service (eks.amazonaws.com).
# No human or application assumes this role - only EKS itself.

resource "aws_iam_role" "cluster" {
  name        = "lsd-payments-dev-cluster-role"
  description = "Role used by EKS control plane to call AWS APIs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "lsd-payments-dev-cluster-role"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# Attach the AWS managed policy for EKS clusters.
# This policy contains all the permissions EKS needs.
# AWS maintains it so if EKS needs new permissions in future
# they update the policy and your cluster gets them automatically.

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ## EKS CLUSTER #########################################################
# The cluster resource creates the Kubernetes control plane.
# AWS runs the API server, scheduler, and etcd on your behalf.
# You never see or manage those machines.
#
# endpoint_private_access = true means kubectl can reach the API
# server from inside the VPC (from your nodes and from a bastion).
#
# endpoint_public_access = true means you can also reach it from
# your laptop. In a real production setup you would set this to
# false and only allow access from inside the VPC.
# For a demo we keep it true so we can run kubectl locally.
#
# enabled_cluster_log_types sends control plane logs to CloudWatch.
# audit logs are the important ones - they record every API call
# made to your cluster which is critical for security investigations.

resource "aws_eks_cluster" "main" {
  name     = "lsd-payments-dev"
  role_arn = aws_iam_role.cluster.arn
  version  = "1.30"

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Name        = "lsd-payments-dev"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  # The cluster cannot exist without the role being ready
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}


# ## OIDC PROVIDER #####################################################
# OIDC stands for OpenID Connect. It is an identity protocol.
#
# Every EKS cluster has its own OIDC issuer URL.
# By registering that URL as a trusted provider in IAM, you enable
# pods inside the cluster to prove their identity to AWS.
#
# Without this: every pod that needs AWS access needs static credentials
# stored as a secret somewhere.
#
# With this: a pod says "I am the ALB controller service account in
# namespace kube-system" and AWS verifies that claim against the
# cluster's OIDC provider and issues temporary credentials.
# No secrets stored anywhere.
#
# data "tls_certificate" reads the certificate from the OIDC endpoint.
# The thumbprint is a fingerprint of that certificate.
# AWS uses it to verify the OIDC provider is legitimate.

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = {
    Name        = "lsd-payments-dev-oidc"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ## NODE IAM ROLE ######################################################
# Your EC2 worker nodes need an IAM role too.
# They use it to:
#   - Pull container images from ECR
#   - Register themselves with the cluster
#   - Manage pod networking via the VPC CNI plugin
#
# The assume_role_policy here says:
# "the EC2 service is allowed to assume this role"
# meaning when an EC2 instance starts up it automatically
# gets the permissions attached to this role.

resource "aws_iam_role" "node" {
  name        = "lsd-payments-dev-node-role"
  description = "Role used by EKS worker nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "lsd-payments-dev-node-role"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# Three managed policies cover everything the nodes need.
# AmazonEKSWorkerNodePolicy  - lets nodes join the cluster
# AmazonEC2ContainerRegistryReadOnly - lets nodes pull images from ECR
# AmazonEKS_CNI_Policy - lets the VPC CNI plugin manage pod networking

resource "aws_iam_role_policy_attachment" "node_eks_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# ## LAUNCH TEMPLATE ######################################################
# A launch template is a configuration blueprint for EC2 instances.
# Every node that starts uses this template.
#
# The only thing we configure here is IMDSv2.
# IMDS is the Instance Metadata Service - it runs on every EC2 node
# at http://169.254.169.254 and answers questions like
# "what IAM role do I have" and "what region am I in".
#
# http_tokens = "required" means IMDSv2 is enforced.
# IMDSv2 requires a session token before it answers any query.
# This blocks a common attack where a compromised pod makes a request
# to the metadata service and steals the node's IAM credentials.
# With IMDSv2 that attack does not work because the pod cannot get
# the session token needed to query the metadata service.
#
# http_put_response_hop_limit = 1 means the metadata response
# cannot travel more than one network hop. A pod is two hops
# away from the metadata service so even if it tries it cannot
# reach it. Extra defence on top of IMDSv2.

resource "aws_launch_template" "node" {
  name        = "lsd-payments-dev-node-lt"
  description = "Launch template for EKS nodes - enforces IMDSv2"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "lsd-payments-dev-node"
      Project     = "lsd-payments"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}


# ## MANAGED NODE GROUP ####################################################
# The node group is the pool of EC2 instances that run your pods.
# Managed means AWS handles OS patching and node replacement.
#
# t3.medium gives you 2 vCPU and 4GB RAM per node.
# For a demo that is sufficient. Production would use larger instances.
#
# scaling_config defines how many nodes you want.
# desired = 2 means start with 2 nodes.
# min = 1 means never go below 1 (cost saving).
# max = 4 means never go above 4 (cost protection).
#
# The nodes go in private subnets - they have no public IP
# and are not directly reachable from the internet.
#
# depends_on the three policy attachments because the node
# cannot join the cluster until its role has all three policies.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "lsd-payments-dev-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = "AL2_x86_64"
  instance_types  = ["t3.small"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  tags = {
    Name        = "lsd-payments-dev-nodes"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_eks_worker,
    aws_iam_role_policy_attachment.node_ecr_read,
    aws_iam_role_policy_attachment.node_cni
  ]
}


# ## EKS ADD-ONS ######################################################
# Add-ons are core Kubernetes components that AWS manages for you.
# AWS keeps them patched and updated automatically.
#
# vpc-cni: gives every pod its own IP address from your VPC CIDR.
#   Without this pods cannot communicate with each other or with AWS services.
#
# coredns: handles DNS inside the cluster.
#   When a pod says "connect to eks-demo-backend" CoreDNS resolves
#   that name to the right pod IP address.
#   depends_on the node group because CoreDNS pods need nodes to run on.
#
# kube-proxy: runs on every node and manages network routing rules.
#   It ensures traffic to a Service IP gets forwarded to the right pod.
#
# aws-ebs-csi-driver: lets pods request persistent storage volumes.
#   Without this your database pod cannot write data that survives a restart.
#   depends_on the node group because it needs nodes to run on.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_eks_node_group.main]
}
