# ─── OpenSearch MCP Server Lambda ────────────────────────────────────────────

variable "enable_mcp_server" {
  description = "Deploy the OpenSearch MCP Server Lambda"
  type        = bool
  default     = true
}

variable "mcp_server_auth_type" {
  description = "Function URL auth type (AWS_IAM or NONE)"
  type        = string
  default     = "AWS_IAM"
}

# ─── Build the deployment package ────────────────────────────────────────────

resource "null_resource" "mcp_server_build" {
  count = var.enable_mcp_server ? 1 : 0

  triggers = {
    requirements = filemd5("${path.module}/mcp-server/requirements.txt")
    handler      = filemd5("${path.module}/mcp-server/handler.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/.build/mcp-server
      mkdir -p ${path.module}/.build/mcp-server
      pip install -r ${path.module}/mcp-server/requirements.txt \
        -t ${path.module}/.build/mcp-server \
        --platform manylinux2014_aarch64 \
        --implementation cp \
        --python-version 3.12 \
        --only-binary=:all: \
        --quiet 2>/dev/null || \
      pip install -r ${path.module}/mcp-server/requirements.txt \
        -t ${path.module}/.build/mcp-server \
        --quiet
      cp ${path.module}/mcp-server/handler.py ${path.module}/.build/mcp-server/
    EOT
  }
}

data "archive_file" "mcp_server_zip" {
  count       = var.enable_mcp_server ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/.build/mcp-server"
  output_path = "${path.module}/.build/mcp-server.zip"
  depends_on  = [null_resource.mcp_server_build]
}

# ─── IAM Role ────────────────────────────────────────────────────────────────

resource "aws_iam_role" "mcp_server_role" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "${var.project_name}-mcp-server-role"

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

resource "aws_iam_role_policy" "mcp_server_policy" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "mcp-server"
  role  = aws_iam_role.mcp_server_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = "arn:aws:aoss:${var.region}:${var.account_id}:collection/*"
      }
    ]
  })
}

# ─── Lambda Function ─────────────────────────────────────────────────────────

resource "aws_lambda_function" "mcp_server" {
  count            = var.enable_mcp_server ? 1 : 0
  function_name    = "${var.project_name}-mcp-server"
  role             = aws_iam_role.mcp_server_role[0].arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.mcp_server_zip[0].output_path
  source_code_hash = data.archive_file.mcp_server_zip[0].output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      OPENSEARCH_URL           = aws_opensearchserverless_collection.logs.collection_endpoint
      OPENSEARCH_IS_SERVERLESS = "true"
      AWS_REGION_NAME          = var.region
    }
  }

  tags = { Project = var.project_name }
}

resource "aws_cloudwatch_log_group" "mcp_server_logs" {
  count             = var.enable_mcp_server ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-mcp-server"
  retention_in_days = 7
  tags              = { Project = var.project_name }
}

# ─── Function URL ────────────────────────────────────────────────────────────

resource "aws_lambda_function_url" "mcp_server" {
  count              = var.enable_mcp_server ? 1 : 0
  function_name      = aws_lambda_function.mcp_server[0].function_name
  authorization_type = var.mcp_server_auth_type

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "DELETE"]
    allow_headers = ["*"]
  }
}

# ─── AOSS Data Access Policy (add MCP server role) ──────────────────────────

resource "aws_opensearchserverless_access_policy" "mcp_data" {
  count = var.enable_mcp_server ? 1 : 0
  name  = "${var.project_name}-mcp-data"
  type  = "data"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${var.project_name}-logs"]
        Permission   = ["aoss:CreateCollectionItems", "aoss:UpdateCollectionItems", "aoss:DescribeCollectionItems"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${var.project_name}-logs/*"]
        Permission = [
          "aoss:CreateIndex", "aoss:UpdateIndex", "aoss:DescribeIndex",
          "aoss:ReadDocument", "aoss:WriteDocument"
        ]
      }
    ]
    Principal = [aws_iam_role.mcp_server_role[0].arn]
  }])
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "mcp_server_function_url" {
  value       = var.enable_mcp_server ? aws_lambda_function_url.mcp_server[0].function_url : ""
  description = "OpenSearch MCP Server endpoint (Streamable HTTP)"
}

output "mcp_server_function_name" {
  value       = var.enable_mcp_server ? aws_lambda_function.mcp_server[0].function_name : ""
  description = "MCP Server Lambda function name"
}
