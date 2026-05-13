# ═══════════════════════════════════════════
# Lambda Origins — one per region
# ═══════════════════════════════════════════

data "archive_file" "origin_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/origin.py"
  output_path = "${path.module}/.build/origin.zip"
}

# IAM Role (shared across regions)
resource "aws_iam_role" "lambda_role" {
  name = "${local.project}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Americas (us-east-1) ──
resource "aws_lambda_function" "origin_americas" {
  provider      = aws.us_east_1
  function_name = "${local.project}-origin-americas"
  role          = aws_iam_role.lambda_role.arn
  handler       = "origin.handler"
  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.origin_lambda.output_path
  source_code_hash = data.archive_file.origin_lambda.output_base64sha256

  environment {
    variables = {
      AWS_REGION_NAME = "us-east-1"
      ORIGIN_LABEL    = "Americas (us-east-1)"
    }
  }
}


# ── EMEA (eu-west-1) ──
resource "aws_lambda_function" "origin_emea" {
  provider      = aws.eu_west_1
  function_name = "${local.project}-origin-emea"
  role          = aws_iam_role.lambda_role.arn
  handler       = "origin.handler"
  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.origin_lambda.output_path
  source_code_hash = data.archive_file.origin_lambda.output_base64sha256

  environment {
    variables = {
      AWS_REGION_NAME = "eu-west-1"
      ORIGIN_LABEL    = "EMEA (eu-west-1)"
    }
  }
}


# ── APAC (ap-southeast-1) ──
resource "aws_lambda_function" "origin_apac" {
  provider      = aws.ap_southeast_1
  function_name = "${local.project}-origin-apac"
  role          = aws_iam_role.lambda_role.arn
  handler       = "origin.handler"
  runtime       = "python3.12"
  architectures = ["arm64"]
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.origin_lambda.output_path
  source_code_hash = data.archive_file.origin_lambda.output_base64sha256

  environment {
    variables = {
      AWS_REGION_NAME = "ap-southeast-1"
      ORIGIN_LABEL    = "APAC (ap-southeast-1)"
    }
  }
}

