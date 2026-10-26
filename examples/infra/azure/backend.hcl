# Values printed by bootstrap/azure (output "backend_config").
resource_group_name  = "rg-tfgha-tfstate"
storage_account_name = "sttfghatfstate000000"
container_name       = "tfstate"
key                  = "examples/infra/azure.tfstate"
use_oidc             = true
use_azuread_auth     = true
