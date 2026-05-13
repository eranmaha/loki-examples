terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider (us-east-1)
provider "aws" {
  region = "us-east-1"
  alias  = "us_east_1"
}

provider "aws" {
  region = "eu-west-1"
  alias  = "eu_west_1"
}

provider "aws" {
  region = "ap-southeast-1"
  alias  = "ap_southeast_1"
}

# For Route 53 (global)
provider "aws" {
  region = "us-east-1"
}

variable "domain_name" {
  description = "Subdomain for geo routing demo (e.g. geo.example.com)"
  type        = string
  default     = "geo-demo"
}

locals {
  project = "geo-routing-dns"
  origins = {
    americas = {
      region   = "us-east-1"
      label    = "Americas (us-east-1)"
    }
    emea = {
      region   = "eu-west-1"
      label    = "EMEA (eu-west-1)"
    }
    apac = {
      region   = "ap-southeast-1"
      label    = "APAC (ap-southeast-1)"
    }
  }
}
