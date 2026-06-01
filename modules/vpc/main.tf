# ##############################################################################
# VPC MODULE - lsd-payments
#
# What gets created:
#   1 VPC
#   3 public subnets  (one per AZ) - for the load balancer
#   3 private subnets (one per AZ) - for nodes and database
#   1 internet gateway
#   1 NAT gateway     (single - sufficient for demo, saves cost)
#   1 EIP             (for the single NAT gateway)
#   Route tables      (traffic rules for each subnet)
#
# Cost saving vs 3 NAT gateways:
#   3 NAT gateways = ~$0.135/hour
#   1 NAT gateway  = ~$0.045/hour
#   Saving         = ~$0.09/hour (~$65/month if left running)
#
# Trade-off: if us-east-2a goes down, private subnets in 2b and 2c
# lose outbound internet access. Acceptable for a demo environment.
# ##############################################################################


# ##############################################################################
# VPC
# ##############################################################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "lsd-payments-vpc"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ##############################################################################
# PUBLIC SUBNETS
# Load balancer lives here. One per AZ for redundancy.
# kubernetes.io/role/elb tag required for ALB controller discovery.
# ##############################################################################

resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "lsd-payments-public-az1"
    "kubernetes.io/role/elb" = "1"
    Project                  = "lsd-payments"
    Environment              = "dev"
    ManagedBy                = "terraform"
  }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "lsd-payments-public-az2"
    "kubernetes.io/role/elb" = "1"
    Project                  = "lsd-payments"
    Environment              = "dev"
    ManagedBy                = "terraform"
  }
}

resource "aws_subnet" "public_az3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-2c"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "lsd-payments-public-az3"
    "kubernetes.io/role/elb" = "1"
    Project                  = "lsd-payments"
    Environment              = "dev"
    ManagedBy                = "terraform"
  }
}


# ##############################################################################
# PRIVATE SUBNETS
# EKS nodes and RDS live here. No direct internet access.
# kubernetes.io/role/internal-elb tag required for ALB controller.
# ##############################################################################

resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name                              = "lsd-payments-private-az1"
    "kubernetes.io/role/internal-elb" = "1"
    Project                           = "lsd-payments"
    Environment                       = "dev"
    ManagedBy                         = "terraform"
  }
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name                              = "lsd-payments-private-az2"
    "kubernetes.io/role/internal-elb" = "1"
    Project                           = "lsd-payments"
    Environment                       = "dev"
    ManagedBy                         = "terraform"
  }
}

resource "aws_subnet" "private_az3" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.13.0/24"
  availability_zone = "us-east-2c"

  tags = {
    Name                              = "lsd-payments-private-az3"
    "kubernetes.io/role/internal-elb" = "1"
    Project                           = "lsd-payments"
    Environment                       = "dev"
    ManagedBy                         = "terraform"
  }
}


# ##############################################################################
# INTERNET GATEWAY
# The VPCs connection to the internet.
# Required for public subnets to receive and send internet traffic.
# ##############################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "lsd-payments-igw"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ##############################################################################
# SINGLE EIP AND NAT GATEWAY
#
# One NAT gateway in az1 only.
# All three private subnets route outbound traffic through this one gateway.
# Cost: ~$0.045/hour vs ~$0.135/hour for three gateways.
#
# The NAT gateway sits in the PUBLIC subnet so it can reach the internet.
# Private subnets route TO it - it then forwards traffic OUT through the IGW.
# ##############################################################################

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name        = "lsd-payments-nat-eip"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_az1.id

  tags = {
    Name        = "lsd-payments-nat"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ##############################################################################
# PUBLIC ROUTE TABLE
# All public subnets share this one route table.
# Rule: all traffic goes to the internet gateway.
# This is what makes a subnet public.
# ##############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "lsd-payments-public-rt"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az3" {
  subnet_id      = aws_subnet.public_az3.id
  route_table_id = aws_route_table.public.id
}


# ##############################################################################
# PRIVATE ROUTE TABLE
#
# Single route table shared by all three private subnets.
# All outbound traffic routes through the one NAT gateway.
#
# In production you would have separate route tables per AZ each
# pointing to their own NAT gateway. If az1 goes down, az2 and az3
# would lose their NAT gateway with this setup.
# For a demo that is an acceptable trade-off.
# ##############################################################################

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "lsd-payments-private-rt"
    Project     = "lsd-payments"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "private_az1" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_az2" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_az3" {
  subnet_id      = aws_subnet.private_az3.id
  route_table_id = aws_route_table.private.id
}
