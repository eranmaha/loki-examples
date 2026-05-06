terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "devops-agent-demo"
}

variable "dsql_cluster_endpoint" {
  default = "zntxnmjv6gxlrwznxhbmxrboza.dsql.us-east-1.on.aws"
}

variable "dsql_cluster_arn" {
  default = "arn:aws:dsql:us-east-1:033216807884:cluster/zntxnmjv6gxlrwznxhbmxrboza"
}

variable "devops_agent_webhook_url" {
  description = "Webhook URL for the DevOps agent (OpenClaw)"
  type        = string
}

variable "lambda_timeout" {
  default = 15
}

# ─── Data Sources ────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── SSM Parameters (for error injection) ───────────────────────────────────

resource "aws_ssm_parameter" "sleep_seconds" {
  name  = "/${var.project_name}/sleep-seconds"
  type  = "String"
  value = "0"
  tags  = { Project = var.project_name }
}

# ─── IAM Role for Lambda ────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "lambda_base" {
  name = "base"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = aws_ssm_parameter.sleep_seconds.arn
      }
    ]
  })
}

# DSQL access policy - separate so we can detach it for error injection
resource "aws_iam_role_policy" "lambda_dsql" {
  name = "dsql-access"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dsql:DbConnectAdmin"]
      Resource = var.dsql_cluster_arn
    }]
  })
}

# ─── Lambda Function ────────────────────────────────────────────────────────

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_lambda_function" "app" {
  function_name    = "${var.project_name}-app"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  architectures    = ["arm64"]
  timeout          = var.lambda_timeout
  memory_size      = 256
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DSQL_ENDPOINT    = var.dsql_cluster_endpoint
      DSQL_REGION      = var.region
      SSM_SLEEP_PARAM  = aws_ssm_parameter.sleep_seconds.name
      PROJECT_NAME     = var.project_name
    }
  }

  tags = { Project = var.project_name }
}

# ─── API Gateway ────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
  }
  tags = { Project = var.project_name }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.app.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  function_name = aws_lambda_function.app.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# ─── CloudFront Distribution ───────────────────────────────────────────────

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  default_root_object = ""
  comment             = "${var.project_name} - Serverless App"

  origin {
    domain_name = replace(aws_apigatewayv2_api.api.api_endpoint, "https://", "")
    origin_id   = "api"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "api"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Project = var.project_name }
}

# ─── CloudWatch Metric Filter + Alarm ──────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.app.function_name}"
  retention_in_days = 7
  tags              = { Project = var.project_name }
}

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.project_name}-error-rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Lambda error rate >= 3 errors in 1 minute"
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.app.function_name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = { Project = var.project_name }
}

resource "aws_cloudwatch_metric_alarm" "timeout_rate" {
  alarm_name          = "${var.project_name}-timeout-rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Maximum"
  threshold           = (var.lambda_timeout - 1) * 1000  # near-timeout in ms
  alarm_description   = "Lambda near-timeout detected (duration >= ${var.lambda_timeout - 1}s)"
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.app.function_name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = { Project = var.project_name }
}

# ─── SNS → DevOps Agent Webhook ────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
  tags = { Project = var.project_name }
}

resource "aws_sns_topic_subscription" "webhook" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.devops_agent_webhook_url
}

# ─── Error Injection Lambda ─────────────────────────────────────────────────

resource "aws_iam_role" "injector_role" {
  name = "${var.project_name}-injector-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "injector_policy" {
  name = "injector"
  role = aws_iam_role.injector_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PutRolePolicy", "iam:DeleteRolePolicy"]
        Resource = aws_iam_role.lambda_role.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:PutParameter", "ssm:GetParameter"]
        Resource = aws_ssm_parameter.sleep_seconds.arn
      }
    ]
  })
}

data "archive_file" "injector_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/injector.js"
  output_path = "${path.module}/.build/injector.zip"
}

resource "aws_lambda_function" "injector" {
  function_name    = "${var.project_name}-injector"
  role             = aws_iam_role.injector_role.arn
  handler          = "injector.handler"
  runtime          = "nodejs20.x"
  architectures    = ["arm64"]
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.injector_zip.output_path
  source_code_hash = data.archive_file.injector_zip.output_base64sha256

  environment {
    variables = {
      APP_ROLE_NAME   = aws_iam_role.lambda_role.name
      SSM_SLEEP_PARAM = aws_ssm_parameter.sleep_seconds.name
      DSQL_POLICY_NAME = "dsql-access"
    }
  }

  tags = { Project = var.project_name }
}

resource "aws_apigatewayv2_integration" "injector" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.injector.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "inject" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /inject"
  target    = "integrations/${aws_apigatewayv2_integration.injector.id}"
}

resource "aws_lambda_permission" "injector_apigw" {
  function_name = aws_lambda_function.injector.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# ─── Outputs ────────────────────────────────────────────────────────────────

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "api_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "test_page_url" {
  value = "https://${aws_cloudfront_distribution.app.domain_name}/test"
}

output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}

output "alarm_error_rate" {
  value = aws_cloudwatch_metric_alarm.error_rate.alarm_name
}

output "alarm_timeout" {
  value = aws_cloudwatch_metric_alarm.timeout_rate.alarm_name
}
