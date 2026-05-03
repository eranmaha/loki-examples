output "global_accelerator_dns" {
  description = "Global Accelerator DNS name (anycast endpoint)"
  value       = module.global_accelerator.dns_name
}

output "global_accelerator_ips" {
  description = "Global Accelerator static IPs"
  value       = module.global_accelerator.static_ips
}

output "alb_dns" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "logs_bucket" {
  description = "S3 bucket for all observability logs"
  value       = aws_s3_bucket.logs.id
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.observability.dashboard_url
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}
