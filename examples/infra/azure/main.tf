data "azurerm_client_config" "current" {}

locals {
  # Storage account names are global; a short hash of the subscription keeps the
  # name deterministic without an extra provider.
  suffix = substr(md5(data.azurerm_client_config.current.subscription_id), 0, 6)

  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
    source      = "terraform-github-actions-oidc"
  })
}

resource "azurerm_resource_group" "demo" {
  name     = "rg-${var.name_prefix}-${var.environment}"
  location = var.location
  tags     = local.tags
}

# Disposable demo target, so no prevent_destroy here. Real data stores should have it.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_account" "demo" {
  #checkov:skip=CKV_AZURE_59:Demo target reached from GitHub-hosted runners; shared keys are disabled.
  #checkov:skip=CKV2_AZURE_33:Private endpoints require self-hosted runners in the virtual network.
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys plus infrastructure encryption are enough for a demo.
  #checkov:skip=CKV_AZURE_33:No queues are used.
  #checkov:skip=CKV_AZURE_43:Name is computed and always valid; the check cannot evaluate interpolation.
  #checkov:skip=CKV_AZURE_206:ZRS is the deliberate choice for a disposable demo.
  name                = "st${var.name_prefix}${var.environment}${local.suffix}"
  resource_group_name = azurerm_resource_group.demo.name
  location            = azurerm_resource_group.demo.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}
