# ─── Networking ────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.project_name}-private-${count.index}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ─── VPC Flow Logs ────────────────────────────────────────────────────────────

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_log.arn
  log_format           = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${tcp-flags} $${flow-direction} $${pkt-srcaddr} $${pkt-dstaddr}"

  tags = { Name = "${var.project_name}-vpc-flow-logs" }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.project_name}"
  retention_in_days = 14
}

resource "aws_iam_role" "flow_log" {
  name = "${var.project_name}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name = "flow-log-publish"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

# ─── S3 Bucket for Logs ──────────────────────────────────────────────────────

resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-logs-${var.account_id}"

  tags = { Name = "${var.project_name}-logs" }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── Modules ─────────────────────────────────────────────────────────────────

module "global_accelerator" {
  source = "./modules/global-accelerator"

  project_name = var.project_name
  alb_arn      = module.alb.alb_arn
  logs_bucket  = aws_s3_bucket.logs.id
}

module "alb" {
  source = "./modules/alb"

  project_name   = var.project_name
  vpc_id         = aws_vpc.main.id
  public_subnets = aws_subnet.public[*].id
  logs_bucket    = aws_s3_bucket.logs.id
  account_id     = var.account_id
  region         = var.primary_region
}

module "eks" {
  source = "./modules/eks"

  project_name     = var.project_name
  cluster_name     = var.eks_cluster_name
  vpc_id           = aws_vpc.main.id
  private_subnets  = aws_subnet.private[*].id
  alb_target_group = module.alb.target_group_arn
  dsql_endpoint    = var.dsql_endpoint_primary
  region           = var.primary_region
  account_id       = var.account_id
}

module "edge_simulator" {
  source = "./modules/edge-simulator"

  project_name        = var.project_name
  ga_endpoint         = module.global_accelerator.dns_name
  account_id          = var.account_id
  primary_region      = var.primary_region
}

module "observability" {
  source = "./modules/observability"

  project_name         = var.project_name
  vpc_flow_log_group   = aws_cloudwatch_log_group.vpc_flow_logs.name
  eks_cluster_name     = var.eks_cluster_name
  alb_arn_suffix       = module.alb.alb_arn_suffix
  ga_accelerator_arn   = module.global_accelerator.accelerator_arn
  region               = var.primary_region
}
