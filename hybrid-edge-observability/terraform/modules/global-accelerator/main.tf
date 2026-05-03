variable "project_name" { type = string }
variable "alb_arn" { type = string }
variable "logs_bucket" { type = string }

resource "aws_globalaccelerator_accelerator" "main" {
  name            = "${var.project_name}-ga"
  ip_address_type = "IPV4"
  enabled         = true

  attributes {
    flow_logs_enabled   = true
    flow_logs_s3_bucket = var.logs_bucket
    flow_logs_s3_prefix = "ga-flow-logs/"
  }
}

resource "aws_globalaccelerator_listener" "http" {
  accelerator_arn = aws_globalaccelerator_accelerator.main.id
  protocol        = "TCP"

  port_range {
    from_port = 80
    to_port   = 80
  }
}

resource "aws_globalaccelerator_listener" "https" {
  accelerator_arn = aws_globalaccelerator_accelerator.main.id
  protocol        = "TCP"

  port_range {
    from_port = 443
    to_port   = 443
  }
}

resource "aws_globalaccelerator_endpoint_group" "primary" {
  listener_arn = aws_globalaccelerator_listener.http.id

  endpoint_configuration {
    endpoint_id = var.alb_arn
    weight      = 100
  }

  health_check_port     = 80
  health_check_protocol = "HTTP"
  health_check_path     = "/health"

  threshold_count                = 3
  health_check_interval_seconds  = 10
}

output "dns_name" {
  value = aws_globalaccelerator_accelerator.main.dns_name
}

output "static_ips" {
  value = aws_globalaccelerator_accelerator.main.ip_sets[*].ip_addresses
}

output "accelerator_arn" {
  value = aws_globalaccelerator_accelerator.main.id
}
