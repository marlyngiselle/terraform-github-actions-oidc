# Troubleshooting

Most failures fall into three groups: the token is never issued, the cloud rejects the token,
or the session works but lacks a permission. The error text tells you which.

## The token is never issued

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Unable to get ACTIONS_ID_TOKEN_REQUEST_URL env variable` | The calling job did not grant `id-token: write` | Add `permissions: { contents: read, id-token: write }` to the job that calls the reusable workflow. A called workflow can never gain permissions its caller did not grant |
| Same error, only on pull requests from forks | Fork runs never receive `id-token: write` | Expected. Plans for fork contributions run after a maintainer pushes the branch to the main repository |
| `The nested job 'plan' is requesting 'pull-requests: write', but is only allowed 'none'` | Caller sets `permissions: {}` without granting the job permissions | Grant the permissions listed in the [security model](security-model.md#6-least-privilege-github_token) on the calling job |

## The cloud rejects the token

Start by printing the subject the job actually presents. Add this step temporarily before the
login step:

```yaml
- name: Show OIDC claims
  uses: actions/github-script@v9
  with:
    script: |
      const token = await core.getIDToken('api://AzureADTokenExchange');
      const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
      core.info(JSON.stringify({ sub: claims.sub, aud: claims.aud, ref: claims.ref, environment: claims.environment }, null, 2));
```

The token is only a claim set and expires in minutes, but remove the step once you have the
answer.

| Symptom | Cause | Fix |
| --- | --- | --- |
| Azure `AADSTS70021` or `AADSTS700213`: no matching federated identity record for the subject | The `sub` claim does not match any federated credential on that application | Compare the printed `sub` with `terraform output federated_subjects`. Common mismatches: wrong identity for the job (apply client ID used in a pull request), branch name differs, environment name case differs |
| Azure `AADSTS700211` (issuer) or `AADSTS700212` (audience) | Issuer or audience mismatch | Issuer must be `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange` |
| AWS `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy conditions do not match | Check `sub` and `aud` against `aws iam get-role --role-name <role>`; the audience must be `sts.amazonaws.com` |
| AWS `No OpenIDConnect provider found in your account for https://token.actions.githubusercontent.com` | Provider missing, or created in another account | Apply `bootstrap/aws` with `create_oidc_provider = true` in the account that owns the role |
| Subject is `repo:ORG/REPO:environment:prod` in a plan job | The plan job was given an `environment` | Plans should not declare an environment; the environment subject belongs to the apply identity |
| Subjects stopped matching after a repository rename or transfer | `sub` contains the new `owner/repo` | Re-apply the bootstrap with the new names, or move to a subject template based on immutable IDs |

## The session works but an operation fails

| Symptom | Cause | Fix |
| --- | --- | --- |
| `AuthorizationPermissionMismatch` or `403 This request is not authorized` on the state blob | Missing `Storage Blob Data Contributor` on the container, or the role assignment is still propagating | Check the assignment from `bootstrap/azure`. New assignments can take a few minutes to apply |
| `Key based authentication is not permitted on this storage account` | Backend falls back to access keys | Set `use_azuread_auth = true` in `backend.hcl` and `storage_use_azuread = true` in the provider |
| Plan on Azure fails with `listKeys` permission errors | A resource's refresh calls an action that `Reader` lacks (some resources read keys during refresh) | Prefer settings that avoid keys (for example `shared_access_key_enabled = false`). Otherwise grant the plan identity a custom role with that one read action |
| AWS `AccessDenied` on `<key>.tflock` | IAM policy misses `s3:PutObject` or `s3:DeleteObject` for the lock file | Both roles need them on `bucket/*`; see `aws_iam_role_policy.state_access` |
| `Error acquiring the state lock` | Another run holds the lock, or a cancelled run left it | Wait for the other run (the workflows use `-lock-timeout=5m`). If a lock is orphaned, confirm no run is active, then `terraform force-unlock <ID>` locally |

## Apply-specific failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Saved plan is stale` | The state changed between plan and apply (another apply, manual change) | Re-run the workflow. A new plan is produced and must be approved again |
| `plan was created for <sha> but this run is deploying <sha>` | The artifact belongs to a different commit | Use the `plan-artifact` output of the plan job in the same run, never a fixed name |
| `sha256sum: WARNING: 1 computed checksum did NOT match` | The artifact changed after the plan job uploaded it | Treat as a security event. Re-run from scratch and review who can write to Actions artifacts |
| `the given plan file was created by Terraform x, but this is Terraform y` | `terraform-version` differs between plan and apply | Pass the same `terraform-version` to both workflows |
| `Provider dependency changes detected` with `-lockfile=readonly` | Lock file in the artifact does not cover the runner platform | Run `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` and commit the lock file |
| Apply waits forever | Pending approval on the environment | Approve in the run page. A second queued run on the same state replaces any earlier pending one |

## Static checks

| Symptom | Fix |
| --- | --- |
| `terraform fmt` fails | Run `terraform fmt -recursive` locally, or install the pre-commit hooks |
| Checkov fails on a finding you accept | Add `#checkov:skip=<ID>:<reason>` inside the resource block, with a reason a reviewer can judge. Use `checkov-skip-checks` only for organization-wide exceptions |
| TFLint `Failed to install a plugin` with rate limit messages | The workflow passes `GITHUB_TOKEN` to `tflint --init`; on self-hosted runners make sure outbound access to `github.com` is allowed |
| Drift issue keeps reopening | The plan shows changes on every run, often from attributes set outside Terraform | Fix the code, or add a narrowly scoped `lifecycle { ignore_changes = [...] }` with a comment explaining why |
