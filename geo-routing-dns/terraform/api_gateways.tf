# ═══════════════════════════════════════════
# API Gateway endpoints for each origin (replacing Function URLs)
# ═══════════════════════════════════════════

# ── Americas ──
resource "aws_apigatewayv2_api" "americas" {
  provider      = aws.us_east_1
  name          = "${local.project}-americas"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_integration" "americas" {
  provider           = aws.us_east_1
  api_id             = aws_apigatewayv2_api.americas.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.origin_americas.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "americas" {
  provider  = aws.us_east_1
  api_id    = aws_apigatewayv2_api.americas.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.americas.id}"
}

resource "aws_apigatewayv2_route" "americas_root" {
  provider  = aws.us_east_1
  api_id    = aws_apigatewayv2_api.americas.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.americas.id}"
}

resource "aws_apigatewayv2_stage" "americas" {
  provider    = aws.us_east_1
  api_id      = aws_apigatewayv2_api.americas.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "americas_apigw" {
  provider      = aws.us_east_1
  statement_id  = "AllowAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.origin_americas.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.americas.execution_arn}/*/*"
}

# ── EMEA ──
resource "aws_apigatewayv2_api" "emea" {
  provider      = aws.eu_west_1
  name          = "${local.project}-emea"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_integration" "emea" {
  provider           = aws.eu_west_1
  api_id             = aws_apigatewayv2_api.emea.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.origin_emea.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "emea" {
  provider  = aws.eu_west_1
  api_id    = aws_apigatewayv2_api.emea.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.emea.id}"
}

resource "aws_apigatewayv2_route" "emea_root" {
  provider  = aws.eu_west_1
  api_id    = aws_apigatewayv2_api.emea.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.emea.id}"
}

resource "aws_apigatewayv2_stage" "emea" {
  provider    = aws.eu_west_1
  api_id      = aws_apigatewayv2_api.emea.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "emea_apigw" {
  provider      = aws.eu_west_1
  statement_id  = "AllowAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.origin_emea.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.emea.execution_arn}/*/*"
}

# ── APAC ──
resource "aws_apigatewayv2_api" "apac" {
  provider      = aws.ap_southeast_1
  name          = "${local.project}-apac"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_integration" "apac" {
  provider           = aws.ap_southeast_1
  api_id             = aws_apigatewayv2_api.apac.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.origin_apac.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "apac" {
  provider  = aws.ap_southeast_1
  api_id    = aws_apigatewayv2_api.apac.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.apac.id}"
}

resource "aws_apigatewayv2_route" "apac_root" {
  provider  = aws.ap_southeast_1
  api_id    = aws_apigatewayv2_api.apac.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.apac.id}"
}

resource "aws_apigatewayv2_stage" "apac" {
  provider    = aws.ap_southeast_1
  api_id      = aws_apigatewayv2_api.apac.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apac_apigw" {
  provider      = aws.ap_southeast_1
  statement_id  = "AllowAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.origin_apac.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.apac.execution_arn}/*/*"
}
