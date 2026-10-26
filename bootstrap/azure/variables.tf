variable "tenant_id" {
  description = "Entra ID tenant that will trust GitHub's OIDC issuer."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "subscription_id" {
  description = "Subscription that hosts the state storage account and, by default, the deployment scope."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "github_owner" {
  description = "GitHub organization or user that owns the infrastructure repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_owner))
    error_message = "github_owner must be a literal name: wildcards would widen the OIDC trust."
  }
}

variable "github_repository" {
  description = "Name of the repository whose workflows may request tokens (without the owner)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be a literal name: wildcards would widen the OIDC trust."
  }
}

variable "plan_branch" {
  description = "Branch whose workflow runs (push and schedule) may use the read-only plan identity."
  type        = string
  default     = "main"
}

variable "apply_environment" {
  description = "GitHub Environment whose jobs may use the write-capable apply identity. Protect it with required reviewers."
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Short prefix used for every resource name."
  type        = string
  default     = "tfgha"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 10 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region for the state resources."
  type        = string
  default     = "westeurope"
}

variable "deployment_scope" {
  description = "Scope the plan and apply identities act on. Defaults to the whole subscription; narrow it to a resource group where possible."
  type        = string
  default     = null
}

variable "plan_role_definition_name" {
  description = "Built-in or custom role granted to the plan identity on the deployment scope."
  type        = string
  default     = "Reader"
}

variable "apply_role_definition_name" {
  description = "Built-in or custom role granted to the apply identity on the deployment scope."
  type        = string
  default     = "Contributor"
}

variable "state_admin_object_ids" {
  description = "Object IDs of humans or groups that need data-plane access to the state container (for example to migrate the bootstrap state)."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every Azure resource."
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "github-actions-oidc"
  }
}
