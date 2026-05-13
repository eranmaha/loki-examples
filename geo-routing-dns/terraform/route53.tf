# ═══════════════════════════════════════════
# Route 53 — Health Checks + Latency-Based Records
# ═══════════════════════════════════════════

locals {
  # Extract API GW hostnames
  americas_host = "${aws_apigatewayv2_api.americas.id}.execute-api.us-east-1.amazonaws.com"
  emea_host     = "${aws_apigatewayv2_api.emea.id}.execute-api.eu-west-1.amazonaws.com"
  apac_host     = "${aws_apigatewayv2_api.apac.id}.execute-api.ap-southeast-1.amazonaws.com"
}

# ── Health Checks ──
resource "aws_route53_health_check" "americas" {
  fqdn              = local.americas_host
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 10

  tags = { Name = "${local.project}-hc-americas" }
}

resource "aws_route53_health_check" "emea" {
  fqdn              = local.emea_host
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 10

  tags = { Name = "${local.project}-hc-emea" }
}

resource "aws_route53_health_check" "apac" {
  fqdn              = local.apac_host
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 10

  tags = { Name = "${local.project}-hc-apac" }
}

# ── Route 53 Hosted Zone ──
resource "aws_route53_zone" "geo_demo" {
  name    = "geo-routing-demo.internal"
  comment = "Demo zone for latency-based geo routing"
}

# ── Latency-Based Records ──
resource "aws_route53_record" "americas" {
  zone_id        = aws_route53_zone.geo_demo.zone_id
  name           = "api.geo-routing-demo.internal"
  type           = "CNAME"
  ttl            = 60
  set_identifier = "americas"

  latency_routing_policy {
    region = "us-east-1"
  }

  health_check_id = aws_route53_health_check.americas.id
  records         = [local.americas_host]
}

resource "aws_route53_record" "emea" {
  zone_id        = aws_route53_zone.geo_demo.zone_id
  name           = "api.geo-routing-demo.internal"
  type           = "CNAME"
  ttl            = 60
  set_identifier = "emea"

  latency_routing_policy {
    region = "eu-west-1"
  }

  health_check_id = aws_route53_health_check.emea.id
  records         = [local.emea_host]
}

resource "aws_route53_record" "apac" {
  zone_id        = aws_route53_zone.geo_demo.zone_id
  name           = "api.geo-routing-demo.internal"
  type           = "CNAME"
  ttl            = 60
  set_identifier = "apac"

  latency_routing_policy {
    region = "ap-southeast-1"
  }

  health_check_id = aws_route53_health_check.apac.id
  records         = [local.apac_host]
}
