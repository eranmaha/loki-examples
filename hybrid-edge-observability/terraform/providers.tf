terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "loki-reports-033216807884"
    key    = "hybrid-edge-observability/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = {
      Project     = "hybrid-edge-observability"
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "hybrid-edge-observability"
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = "hybrid-edge-observability"
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"

  default_tags {
    tags = {
      Project     = "hybrid-edge-observability"
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}
