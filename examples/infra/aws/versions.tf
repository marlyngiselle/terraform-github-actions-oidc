terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: the values live in backend.hcl and are passed with
  # terraform init -backend-config=backend.hcl. Credentials come from the
  # short-lived session the workflow obtains through OIDC.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.tags, {
      environment = var.environment
      managed-by  = "terraform"
      source      = "terraform-github-actions-oidc"
    })
  }
}
