# ############################################################################
# RDS MODULE - lsd-payments
# ############################################################################
# This creates the PostgreSQL database that the backend application reads
# and writes to. It lives in the private subnets with no public access.
# Only the EKS nodes can connect to it.
#
# What gets created:
#   1 DB subnet group    (tells RDS which subnets it can use)
#   1 security group     (firewall - only EKS nodes on port 5432)
#   1 RDS instance       (PostgreSQL 15, encrypted, private only)
# ############################################################################


# ## DB SUBNET GROUP #########################################################
# A DB subnet group is a collection of subnets you give to RDS.
# RDS uses them to place the database instance and its standby replica.
# You must provide subnets in at least two availability zones.
# We give it all three private subnets.

resource "aws_db_subnet_group" "main" {
  name        = "lsd-payments-dev-db-subnet-group"
  description = "Private subnets for RDS - no public access"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name        = "lsd-payments-dev-db-subnet-group"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ## SECURITY GROUP ################################################
# A security group is a firewall that controls traffic to the database.
#
# The ingress rule (inbound) says:
#   - Only allow TCP traffic on port 5432 (PostgreSQL)
#   - Only from the EKS node security group
#   - Nothing else can connect - not your laptop, not the internet
#
# The egress rule (outbound) allows all outbound traffic.
# This is standard - you restrict what comes IN, not what goes OUT.
#
# var.eks_node_sg_id is the security group ID of your EKS nodes.
# It comes from the EKS module output.
# By referencing a security group instead of an IP range, any new
# node that joins the cluster automatically gets access without
# needing to update this rule.

resource "aws_security_group" "rds" {
  name        = "lsd-payments-dev-rds-sg"
  description = "Allow PostgreSQL access from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "lsd-payments-dev-rds-sg"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ## RDS INSTANCE ################################################
# The actual PostgreSQL database instance.
#
# identifier     - the name AWS gives this instance in the console
# engine         - we are using PostgreSQL
# engine_version - PostgreSQL 15 is current LTS
# instance_class - db.t3.micro is the smallest available, fine for a demo
# allocated_storage - 20GB minimum, plenty for demo data
#
# storage_encrypted = true - data at rest is encrypted.
# Always enable this. There is no cost, no performance impact,
# and no reason not to.
#
# publicly_accessible = false - the most important setting here.
# This ensures RDS never gets a public IP address.
# Combined with the security group, the database is completely
# isolated from the internet.
#
# backup_retention_period = 7 - keeps 7 days of automated backups.
# If something goes wrong you can restore to any point in the last week.
#
# skip_final_snapshot = true - when you destroy this with terraform destroy
# it will not create a final backup first. Fine for a demo, set to false
# in production so you do not lose data on accidental destroy.
#
# deletion_protection = false - allows terraform destroy to delete the DB.
# Set to true in production.
#
# The password comes from a random_password resource in the environment
# main.tf and gets stored in Secrets Manager. It never appears in
# your application code or environment variables directly.

resource "aws_db_instance" "main" {
  identifier        = "lsd-payments-dev-postgres"
  engine            = "postgres"
  engine_version    = "15.5"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "lsdpayments"
  username = "lsdadmin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_encrypted       = true
  publicly_accessible     = false
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Name        = "lsd-payments-dev-postgres"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
