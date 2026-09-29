# Integration suite

The suite in this directory applies the module for real in **your** AWS
account and destroys everything afterwards. It complements the contract
tests in `tests/`, which run with `mock_provider`, need no credentials, and
use placeholder VPC and security group IDs on purpose: they prove the
module's interface and rendering, not that AWS accepts it. This suite proves
the latter.

Nothing here is tied to an account, region, or landing zone: the disposable,
subnet-less VPC fixture in `setup/` is created and destroyed by
`terraform test` itself, named with a random suffix so concurrent runs never
collide.

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | A real security group with one ingress rule (SSH from a private CIDR) and one egress rule (HTTPS scoped to the disposable VPC's own CIDR, never left unrestricted) is accepted by the API; `id`, `arn`, `ingress_rule_ids`, and `egress_rule_ids` all return genuine AWS identifiers in the exact shapes the interface promises (`sg-...`, `arn:...:security-group/...`, `sgr-...`); tags merge correctly; everything is destroyed cleanly afterward. | credentials, region | about a minute |

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
make integration-smoke              # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json)
(replace `<ACCOUNT_ID>`): full lifecycle on security groups and their rules,
plus the minimal VPC permissions the disposable fixture in `setup/` needs
(no subnets, gateway, or route table are created, since this module attaches
nothing to a subnet).

`terraform test` runs `tests/` only by default, so this suite never runs in
the credential-free quality pipeline.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is
dispatch-only and assumes a role through GitHub OIDC. It reads everything
account-specific from the protected `integration` environment of the
repository, so the code stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region the security group and its disposable VPC are created in. |

Dispatch with `gh workflow run integration.yml -f suite=smoke`. Protect the
environment with required reviewers so a run cannot be started from a pull
request by anyone with write access.

For this repository's owner the environment is prepared with the sandbox
region; the role ARN is added once the role exists in the sandbox account,
created through the platform's delivery IAM module with the trust policy
above and the subject `repo:hatan4ik/aws.modules.security-group:environment:integration`.
