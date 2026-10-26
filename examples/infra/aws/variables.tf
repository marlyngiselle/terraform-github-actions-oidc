variable "name_prefix" {
  description = "Short prefix used for every resource name."
  type        = string
  default     = "demo"
}

variable "environment" {
  description = "Environment name, used in names and tags."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region for the demo resources."
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
