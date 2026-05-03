variable "project_name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnets" { type = list(string) }
variable "logs_bucket" { type = string }
variable "account_id" { type = string }
variable "region" { type = string }

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # GA doesn't use prefix list — uses its own IPs
    description = "HTTP from Global Accelerator"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from Global Accelerator"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ─── ALB ──────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets

  access_logs {
    bucket  = var.logs_bucket
    prefix  = "alb-access-logs"
    enabled = true
  }

  tags = { Name = "${var.project_name}-alb" }
}

# ─── S3 bucket policy for ALB access logs ────────────────────────────────────

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = var.logs_bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${var.logs_bucket}/alb-access-logs/*"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${var.logs_bucket}/alb-access-logs/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:aws:s3:::${var.logs_bucket}"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "globalaccelerator.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${var.logs_bucket}/ga-flow-logs/*"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "globalaccelerator.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:aws:s3:::${var.logs_bucket}"
      }
    ]
  })
}

# ─── Target Group ─────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "eks" {
  name        = "${var.project_name}-eks-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    path                = "/health"
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-eks-tg" }
}

# ─── Listener ─────────────────────────────────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks.arn
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "alb_arn" {
  value = aws_lb.main.arn
}

output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "alb_arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "target_group_arn" {
  value = aws_lb_target_group.eks.arn
}

output "security_group_id" {
  value = aws_security_group.alb.id
}
