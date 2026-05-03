variable "primary_region" {
  description = "Primary AWS region for the demo"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
  default     = "033216807884"
}

variable "dsql_cluster_id_primary" {
  description = "DSQL multi-region cluster ID (us-east-1)"
  type        = string
  default     = "eftxnubwguc5c4dqr4gdvjct3e"
}

variable "dsql_cluster_id_secondary" {
  description = "DSQL multi-region cluster ID (us-west-2)"
  type        = string
  default     = "5ftxnuflif62znbn33jayhvdoq"
}

variable "dsql_endpoint_primary" {
  description = "DSQL endpoint for primary region"
  type        = string
  default     = "eftxnubwguc5c4dqr4gdvjct3e.dsql.us-east-1.on.aws"
}

variable "dsql_endpoint_secondary" {
  description = "DSQL endpoint for secondary region"
  type        = string
  default     = "5ftxnuflif62znbn33jayhvdoq.dsql.us-west-2.on.aws"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "hybrid-edge-obs"
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "payment-api"
}
