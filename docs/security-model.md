# Security model

The design goal is simple to state: nobody, human or workflow, holds a credential that can
change production outside a reviewed, approved job. Each control below exists to close one
specific path.

## 1. No long-lived secrets

| Classic setup | This repository |
| --- | --- |
| Client secret or access key stored as a GitHub secret | No secret stored anywhere |
| Valid until someone rotates it (often never) | Session expires after about one hour |
| Usable from any machine that copies it | Usable only by a job whose token GitHub signed |
| Leak = incident, rotation, audit | Leak of an identifier = nothing to revoke |

The values the workflows receive are identifiers: tenant ID, subscription ID, client ID,
role ARN, region. They are stored as GitHub variables (not secrets) because knowing them grants
nothing. Possession is replaced by proof: a job proves who it is with a token signed by GitHub,
and the cloud decides what that identity can do.

## 2. Two identities, two blast radii

| | Plan identity | Apply identity |
| --- | --- | --- |
| Trusted subjects | `pull_request`, `ref:refs/heads/main` | `environment:prod` only |
| Azure role | `Reader` on the deployment scope | `Contributor` on the deployment scope |
| AWS policy | `ReadOnlyAccess` | Policies you pass in `apply_policy_arns` |
| State access | Read and lock (blob lease / lock file) | Read, lock and write |
| Reachable by | Any pull request from the repository, scheduled drift checks | Approved jobs in the `prod` environment |

Pull requests run code that has not been reviewed yet. A malicious change to a workflow or to
a Terraform `external` data source could run arbitrary commands in the plan job. Giving that
job a read-only identity caps the damage at reading what the role can read. Write access only
exists in a job that a human approved.

Both identities need write access to the state container or prefix, because Terraform takes a
lock during plan. Granting `Storage Blob Data Contributor` on the single container (Azure), or
`s3:PutObject` on the state bucket only (AWS), keeps that need away from workload data.

## 3. Exact subject matching

Trust is defined with exact subjects, never wildcards:

- Azure federated identity credentials only support exact `subject` values.
- The AWS trust policy uses `StringEquals` on `token.actions.githubusercontent.com:sub` and
  on `aud`. A `StringLike` with `repo:ORG/*` would let every repository in the organization
  assume the role.
- `github_owner` and `github_repository` are validated in Terraform to reject `*`, `?` and
  other characters that could widen the match.

## 4. Environment protection is what makes `environment:prod` meaningful

The `environment:prod` subject is only as strong as the rules on the `prod` environment.
Configure them before adding the apply identity's client ID or role ARN anywhere:

| Setting | Value | Why |
| --- | --- | --- |
| Required reviewers | At least one person or team | A human approves every apply, after reading the plan |
| Prevent self-review | Enabled | The author of the change cannot approve their own deployment |
| Deployment branches and tags | Selected branches: `main` | A pull request that edits a workflow to add `environment: prod` is refused before the job starts |
| Wait timer | Optional | Adds a window to cancel |
| Administrators bypass | Disabled where the plan allows it | Keeps the rule universal |

Pair it with branch protection (or a ruleset) on `main`: required pull request review,
required status checks including the plan job, and no direct pushes.

## 5. The apply job applies exactly what was reviewed

1. The plan job saves the binary plan with `-out=tfplan` and records its SHA-256, the commit
   and the Terraform version in `plan-metadata.json`.
2. The apply job downloads that artifact from the same workflow run, refuses to continue if
   the commit differs from the one being deployed, and verifies the checksum.
3. `terraform init -lockfile=readonly` installs exactly the provider builds recorded at plan
   time.
4. `terraform apply tfplan` applies the saved plan. Terraform itself rejects it if the state
   changed after the plan was taken (stale plan).

What a reviewer approves in the environment gate is therefore what reaches the cloud.

## 6. Least-privilege `GITHUB_TOKEN`

Every reusable workflow starts with `permissions: {}` and grants per job only what that job
uses:

| Job | `contents` | `id-token` | `pull-requests` | `issues` |
| --- | --- | --- | --- | --- |
| plan | read | write | write (plan comment) | |
| apply | read | write | | |
| drift | read | write | | write (drift issue) |

`id-token: write` lets the job request an OIDC token; it does not grant any repository write
access. Callers must grant at least the same permissions to the calling job, since a called
workflow can only reduce them.

Checkout uses `persist-credentials: false`, so the token is not left in `.git/config` for
later steps, including Terraform providers or `local-exec` commands.

## 7. State protection

| Control | Azure | AWS |
| --- | --- | --- |
| Authentication | Entra ID only, `shared_access_key_enabled = false` | IAM only, bucket owner enforced, ACLs disabled |
| Transport | TLS 1.2 minimum, HTTPS only | Bucket policy denies `aws:SecureTransport = false` |
| Encryption at rest | Platform keys with infrastructure (double) encryption | SSE-KMS with bucket key |
| Recovery | Blob versioning, 30-day soft delete for blobs and containers | Versioning, noncurrent versions kept 90 days |
| Deletion guard | `CanNotDelete` management lock and `prevent_destroy` | `prevent_destroy` |
| Public access | Nested public access disallowed | Public access block on all four settings |
| Locking | Blob lease | Native S3 lock file (`use_lockfile = true`), no DynamoDB table |

## 8. Plan artifacts

A saved plan can contain sensitive values in clear text, for example a generated password
that the plan is about to write. The plan artifact is therefore:

- uploaded only when the plan has changes,
- kept for 5 days by default (`artifact-retention-days`),
- visible only to people with read access to the repository's Actions runs.

For public repositories, prefer private infrastructure repositories, or encrypt the plan
before upload and decrypt it in the apply job.

## 9. Supply chain

- Actions are pinned to major version tags, and Dependabot keeps them current. For stricter
  environments, pin to full commit SHAs; Dependabot updates SHA pins too.
- Terraform, TFLint and its plugins are pinned to exact versions.
- `.terraform.lock.hcl` is committed for every root module and carries the hashes for Linux
  and macOS, so CI and laptops resolve the same provider builds.
- The workflows do not use `pull_request_target`, which would give untrusted code access to
  the base repository's permissions.

## Hardening beyond this baseline

| Option | Effect |
| --- | --- |
| Customize the OIDC subject template to include `repository_owner_id` and `repository_id` | Survives a repository rename or transfer; a recreated repository with the same name cannot inherit trust |
| Self-hosted runners in a private network | Allows private endpoints on the state account and on workload resources |
| Separate identities per environment (`environment:dev`, `environment:prod`) | Different roles and scopes per stage |
| Azure custom role instead of `Contributor` | Restrict the apply identity to the resource providers the workload uses |
| AWS permissions boundary on the apply role | Caps privileges even if more policies are attached later |
