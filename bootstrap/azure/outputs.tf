output "plan_client_id" {
  description = "Client ID of the read-only identity. Store it as the repository variable AZURE_PLAN_CLIENT_ID."
  value       = azuread_application.github["plan"].client_id
}

output "apply_client_id" {
  description = "Client ID of the write-capable identity. Store it as the repository variable AZURE_APPLY_CLIENT_ID; it only works from the protected environment."
  value       = azuread_application.github["apply"].client_id
}

output "tenant_id" {
  description = "Tenant ID to store as the repository variable AZURE_TENANT_ID."
  value       = var.tenant_id
}

output "subscription_id" {
  description = "Subscription ID to store as the repository variable AZURE_SUBSCRIPTION_ID."
  value       = var.subscription_id
}

output "federated_subjects" {
  description = "Every OIDC subject Entra ID will accept, by identity."
  value       = { for k, v in local.identities : k => values(v.subjects) }
}

output "backend_config" {
  description = "Contents for a backend.hcl file consumed by terraform init -backend-config."
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${azurerm_storage_account.state.name}"
    container_name       = "${azurerm_storage_container.state.name}"
    key                  = "CHANGE-ME.tfstate"
    use_oidc             = true
    use_azuread_auth     = true
  EOT
}

output "github_cli_commands" {
  description = "Commands that register the non-secret identifiers as GitHub variables."
  value       = <<-EOT
    gh variable set AZURE_TENANT_ID       --repo ${local.repository_slug} --body ${var.tenant_id}
    gh variable set AZURE_SUBSCRIPTION_ID --repo ${local.repository_slug} --body ${var.subscription_id}
    gh variable set AZURE_PLAN_CLIENT_ID  --repo ${local.repository_slug} --body ${azuread_application.github["plan"].client_id}
    gh variable set AZURE_APPLY_CLIENT_ID --repo ${local.repository_slug} --body ${azuread_application.github["apply"].client_id}
  EOT
}
