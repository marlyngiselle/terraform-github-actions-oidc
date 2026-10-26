output "plan_role_arn" {
  description = "ARN of the read-only role. Store it as the repository variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.github["plan"].arn
}

output "apply_role_arn" {
  description = "ARN of the write-capable role. Store it as the repository variable AWS_APPLY_ROLE_ARN; only the protected environment can assume it."
  value       = aws_iam_role.github["apply"].arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider trusted by both roles."
  value       = local.oidc_provider_arn
}

output "state_bucket" {
  description = "Name of the S3 bucket that stores Terraform state."
  value       = aws_s3_bucket.state.bucket
}

output "backend_config" {
  description = "Contents for a backend.hcl file consumed by terraform init -backend-config."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "CHANGE-ME.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}

output "github_cli_commands" {
  description = "Commands that register the non-secret identifiers as GitHub variables."
  value       = <<-EOT
    gh variable set AWS_REGION         --repo ${local.repository_slug} --body ${var.region}
    gh variable set AWS_PLAN_ROLE_ARN  --repo ${local.repository_slug} --body ${aws_iam_role.github["plan"].arn}
    gh variable set AWS_APPLY_ROLE_ARN --repo ${local.repository_slug} --body ${aws_iam_role.github["apply"].arn}
  EOT
}

output "account_id" {
  description = "AWS account the roles and bucket were created in."
  value       = data.aws_caller_identity.current.account_id
}

