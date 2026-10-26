locals {
  github_issuer   = "token.actions.githubusercontent.com"
  repository_slug = "${var.github_owner}/${var.github_repository}"

  # Two roles, two blast radii. The plan role is reachable from pull requests
  # and therefore only reads. The apply role is reachable only from a job bound
  # to a protected GitHub Environment.
  roles = {
    plan = {
      subjects = [
        "repo:${local.repository_slug}:pull_request",
        "repo:${local.repository_slug}:ref:refs/heads/${var.plan_branch}",
      ]
      policy_arns = var.plan_policy_arns
    }
    apply = {
      subjects = [
        "repo:${local.repository_slug}:environment:${var.apply_environment}",
      ]
      policy_arns = var.apply_policy_arns
    }
  }

  role_policy_attachments = merge([
    for role, cfg in local.roles : {
      for arn in cfg.policy_arns : "${role}|${arn}" => { role = role, arn = arn }
    }
  ]...)

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# GitHub OIDC provider
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://${local.github_issuer}"
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  for_each = local.roles

  statement {
    sid     = "GitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact match on purpose: no wildcards, so a fork, another branch or another
    # environment can never satisfy the condition.
    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:sub"
      values   = each.value.subjects
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = local.roles

  name                 = "${var.name_prefix}-github-${var.github_repository}-${each.key}"
  description          = "GitHub Actions ${each.key} role for ${local.repository_slug}"
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = var.max_session_duration
}

resource "aws_iam_role_policy_attachment" "github" {
  for_each = local.role_policy_attachments

  role       = aws_iam_role.github[each.value.role].name
  policy_arn = each.value.arn
}

data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "ReadWriteStateAndLockFiles"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "state_access" {
  for_each = local.roles

  name   = "terraform-state-access"
  role   = aws_iam_role.github[each.key].id
  policy = data.aws_iam_policy_document.state_access.json
}

# ---------------------------------------------------------------------------
# Remote state: versioned, encrypted, private, TLS only.
# Locking uses the S3 native lock file (use_lockfile = true), so no DynamoDB table.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV2_AWS_62:No consumer for object events.
  #checkov:skip=CKV_AWS_144:Cross-region replication is a recovery decision for each platform, not part of this example.
  #checkov:skip=CKV_AWS_18:Access is audited through CloudTrail data events rather than server access logs.
  bucket = "${var.name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
