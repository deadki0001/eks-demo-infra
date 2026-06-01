# ##############################################################################
# ECR MODULE - lsd-payments
#
# ECR is Elastic Container Registry. It is AWS's private Docker image storage.
# When your CI pipeline builds a Docker image it pushes it here.
# When EKS deploys your application it pulls the image from here.
#
# Think of it like a private Docker Hub that lives inside your AWS account.
# Nothing outside your account can pull from it without permission.
#
# What gets created:
#   1 ECR repository for the frontend image
#   1 ECR repository for the backend image
#   1 lifecycle policy per repo (automatic cleanup of old images)
# ##############################################################################


# ##############################################################################
# FRONTEND REPOSITORY
#
# Stores the React frontend Docker images.
#
# image_tag_mutability = "IMMUTABLE" means once you push an image
# with a tag like "abc1234" you cannot overwrite it.
# This is a security and audit control - you can always trace
# exactly which code is running in your cluster.
#
# scan_on_push = true means AWS automatically scans every image
# you push for known vulnerabilities. Your pipeline also runs
# Trivy but this gives you a second opinion using AWS's own scanner.
# ##############################################################################

resource "aws_ecr_repository" "frontend" {
  name                 = "lsd-frontend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "lsd-frontend"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ##############################################################################
# BACKEND REPOSITORY
#
# Stores the Node.js backend Docker images.
# Identical settings to frontend - same security controls apply.
# ##############################################################################

resource "aws_ecr_repository" "backend" {
  name                 = "lsd-backend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "lsd-backend"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ##############################################################################
# LIFECYCLE POLICIES
#
# A lifecycle policy is a set of rules that automatically delete old images.
# Without this your ECR repos grow forever and you pay for storage you
# do not need.
#
# Rule 1: Delete untagged images after 1 day.
#   Untagged images are leftover build artifacts - intermediate layers
#   that did not get a final tag. They serve no purpose after 24 hours.
#
# Rule 2: Keep only the last 10 tagged images.
#   You only ever roll back one or two versions. Keeping 10 is generous.
#   Anything older than that will never be used again.
# ##############################################################################

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
