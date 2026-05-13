output "api_url_americas" {
  value = aws_apigatewayv2_api.americas.api_endpoint
}

output "api_url_emea" {
  value = aws_apigatewayv2_api.emea.api_endpoint
}

output "api_url_apac" {
  value = aws_apigatewayv2_api.apac.api_endpoint
}

output "health_check_americas_id" {
  value = aws_route53_health_check.americas.id
}

output "health_check_emea_id" {
  value = aws_route53_health_check.emea.id
}

output "health_check_apac_id" {
  value = aws_route53_health_check.apac.id
}

output "hosted_zone_id" {
  value = aws_route53_zone.geo_demo.zone_id
}

output "dns_name" {
  value = "api.geo-routing-demo.internal"
}
