variable "name_prefix" {
  description = "Short prefix used for every resource name."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.name_prefix))
    error_message = "name_prefix must be 3 to 8 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Environment name, used in names and tags."
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for the demo resources."
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
