locals {
  repository_slug = "${var.github_owner}/${var.github_repository}"
  scope           = coalesce(var.deployment_scope, "/subscriptions/${var.subscription_id}")

  # Two identities, two blast radii. The plan identity is reachable from pull
  # requests and therefore only reads. The apply identity is reachable only from
  # a job bound to a protected GitHub Environment.
  identities = {
    plan = {
      role = var.plan_role_definition_name
      subjects = {
        pull-request = "repo:${local.repository_slug}:pull_request"
        branch       = "repo:${local.repository_slug}:ref:refs/heads/${var.plan_branch}"
      }
    }
    apply = {
      role = var.apply_role_definition_name
      subjects = {
        environment = "repo:${local.repository_slug}:environment:${var.apply_environment}"
      }
    }
  }

  federated_credentials = merge([
    for identity, cfg in local.identities : {
      for name, subject in cfg.subjects : "${identity}-${name}" => {
        identity = identity
        name     = name
        subject  = subject
      }
    }
  ]...)

  state_container_scope = "${azurerm_storage_account.state.id}/blobServices/default/containers/${azurerm_storage_container.state.name}"
}

data "azuread_client_config" "current" {}

# ---------------------------------------------------------------------------
# Workload identities
# ---------------------------------------------------------------------------

resource "azuread_application" "github" {
  for_each = local.identities

  display_name = "${var.name_prefix}-github-${var.github_repository}-${each.key}"
  owners       = [data.azuread_client_config.current.object_id]
  notes        = "Federated identity for GitHub Actions (${each.key}) in ${local.repository_slug}. No client secrets."
}

resource "azuread_service_principal" "github" {
  for_each = local.identities

  client_id = azuread_application.github[each.key].client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "github" {
  #checkov:skip=CKV_AZURE_249:Subjects are exact repo-scoped values from locals; owner and repository are validated to reject wildcards. Static analysis cannot resolve for_each values.
  for_each = local.federated_credentials

  application_id = azuread_application.github[each.value.identity].id
  display_name   = "github-${each.value.name}"
  description    = "Trusts ${each.value.subject}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value.subject
}

resource "azurerm_role_assignment" "deployment" {
  for_each = local.identities

  scope                = local.scope
  role_definition_name = each.value.role
  principal_id         = azuread_service_principal.github[each.key].object_id
  principal_type       = "ServicePrincipal"
  description          = "GitHub Actions ${each.key} identity for ${local.repository_slug}"
}

# ---------------------------------------------------------------------------
# Remote state: Entra ID only, no access keys
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.name_prefix}-tfstate"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_59:GitHub-hosted runners reach the account over the public endpoint; access is Entra ID only, shared keys are disabled. Use private endpoints with self-hosted runners.
  #checkov:skip=CKV2_AZURE_33:Same reason as CKV_AZURE_59, private endpoints require self-hosted runners in the virtual network.
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys plus infrastructure encryption. Add a customer-managed key if policy requires it.
  #checkov:skip=CKV_AZURE_33:No queues are used in the state account.
  #checkov:skip=CKV_AZURE_43:Name is computed and always valid; the check cannot evaluate interpolation.
  name                = substr("st${var.name_prefix}tfstate${substr(md5(var.subscription_id), 0, 6)}", 0, 24)
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "GZRS"

  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  #checkov:skip=CKV2_AZURE_21:Blob read logging is a diagnostic setting routed to the platform's central workspace, outside this bootstrap.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_management_lock" "state" {
  name       = "do-not-delete-terraform-state"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Holds Terraform state for ${local.repository_slug}."
}

# Both identities need blob write access: the azurerm backend takes a blob
# lease to lock state, even during plan.
resource "azurerm_role_assignment" "state" {
  for_each = local.identities

  scope                = local.state_container_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github[each.key].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "state_admins" {
  for_each = var.state_admin_object_ids

  scope                = local.state_container_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
