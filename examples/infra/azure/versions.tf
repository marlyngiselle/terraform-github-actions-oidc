terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # Partial configuration: the values live in backend.hcl and are passed with
  # terraform init -backend-config=backend.hcl. Authentication comes from the
  # ARM_* environment variables the workflow sets (OIDC, no keys).
  backend "azurerm" {}
}

provider "azurerm" {
  storage_use_azuread = true

  features {}
}
