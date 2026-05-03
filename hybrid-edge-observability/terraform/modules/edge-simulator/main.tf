variable "project_name" { type = string }
variable "ga_endpoint" { type = string }
variable "account_id" { type = string }
variable "primary_region" { type = string }

# ─── Lambda: Edge Simulator ───────────────────────────────────────────────────

data "archive_file" "simulator" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/simulator.zip"
}

# Deploy simulators in 3 regions to simulate geographically distributed edge devices

resource "aws_lambda_function" "simulator_primary" {
  function_name    = "${var.project_name}-edge-sim"
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.simulator.output_path
  source_code_hash = data.archive_file.simulator.output_base64sha256
  role             = aws_iam_role.simulator.arn

  environment {
    variables = {
      GA_ENDPOINT  = var.ga_endpoint
      REGION_LABEL = var.primary_region
    }
  }
}

# ─── IAM ──────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "simulator" {
  name = "${var.project_name}-edge-sim-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "simulator_basic" {
  role       = aws_iam_role.simulator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "simulator_metrics" {
  name = "publish-metrics"
  role = aws_iam_role.simulator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["cloudwatch:PutMetricData"]
      Effect   = "Allow"
      Resource = "*"
      Condition = {
        StringEquals = { "cloudwatch:namespace" = "PaymentEdge/Latency" }
      }
    }]
  })
}

# ─── Scheduled Trigger (every 5 min for continuous traffic) ───────────────────

resource "aws_cloudwatch_event_rule" "simulator_schedule" {
  name                = "${var.project_name}-sim-schedule"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "simulator" {
  rule = aws_cloudwatch_event_rule.simulator_schedule.name
  arn  = aws_lambda_function.simulator_primary.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.simulator_primary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.simulator_schedule.arn
}

output "simulator_function_name" {
  value = aws_lambda_function.simulator_primary.function_name
}
