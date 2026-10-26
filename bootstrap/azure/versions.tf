terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  # The state account has shared keys disabled, so data-plane calls must use Entra ID.
  storage_use_azuread = true

  features {}
}

provider "azuread" {
  tenant_id = var.tenant_id
}
