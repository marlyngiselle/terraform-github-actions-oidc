variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-1"
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
  description = "Name of the repository whose workflows may assume the roles (without the owner)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be a literal name: wildcards would widen the OIDC trust."
  }
}

variable "plan_branch" {
  description = "Branch whose workflow runs (push and schedule) may assume the read-only plan role."
  type        = string
  default     = "main"
}

variable "apply_environment" {
  description = "GitHub Environment whose jobs may assume the apply role. Protect it with required reviewers."
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Short prefix used for every resource name."
  type        = string
  default     = "tfgha"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,16}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 16 lowercase letters, digits or hyphens."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false when the account already has one (only one per issuer URL is allowed)."
  type        = bool
  default     = true
}

variable "plan_policy_arns" {
  description = "Managed policies attached to the plan role. Read-only by design."
  type        = set(string)
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

variable "apply_policy_arns" {
  description = "Managed policies attached to the apply role. Scope these to what the workload actually deploys."
  type        = set(string)
  default     = []
}

variable "max_session_duration" {
  description = "Maximum session length, in seconds, for both roles."
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Tags applied to every resource through the provider default_tags."
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "github-actions-oidc"
  }
}
