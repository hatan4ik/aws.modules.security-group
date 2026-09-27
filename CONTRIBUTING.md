# Contributing

Thank you for improving `aws.modules.security-group`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## This module's interface is frozen for v1

`create`, `name`, `description`, `vpc_id`, `ingress_rules`, `egress_rules`, `tags`, the `aws_security_group.this` / `aws_vpc_security_group_ingress_rule.this` / `aws_vpc_security_group_egress_rule.this` resource labels, and the `id` / `arn` / `ingress_rule_ids` / `egress_rule_ids` outputs were copied byte-for-byte from `aws.modules.ecs-service`'s internal `modules/security-group` submodule (see [docs/DESIGN.md](docs/DESIGN.md)) specifically so that `aws.modules.ecs-service`, `aws.modules.vpc`'s `modules/endpoints`, and `aws.modules.alb` can adopt this module without a resource-address surprise (see [docs/CONSUMERS.md](docs/CONSUMERS.md)). A pull request that renames any of the above, changes a default, or tightens a validation is a breaking change: it needs a major version, an upgrade guide, and, most importantly, a check that it does not silently break one of the three consumers' migration plans. Genuine improvements that would otherwise change the interface belong in `docs/DESIGN.md`'s "Deferred to v2" section, not in the code, until a major version is ready to carry them.

## Integration suites

`tests/integration/` holds credential-driven suites that apply the module for real and destroy everything afterwards. They are never part of `make check` or the quality pipeline. Run them against your own account before a release that touches resource behaviour:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke   # a few minutes; one security group with one ingress and one egress rule, against a disposable VPC fixture, all destroyed afterward
```

Add a suite when a feature's correctness depends on the AWS API rather than on rendering. Keep every value derived from the environment or from disposable fixtures the suite creates, and never reference a real VPC, security group, or account. The disposable VPC fixture lives in `tests/integration/setup`, which the policy scans exclude.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root and every example directory. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root. No credentials are needed. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. CI runs `terraform init` before the docs drift check, so a lock file missing the Linux hash gets rewritten and fails that check. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason on the resource it concerns. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl`, one file per concern: `defaults` (secure defaults, tagging, `create = false`), `rules` (ingress and egress rendering, `self`, multiple rules), `validation` (every variable validation via `expect_failures`), `checks` if any advisory checks are added later. Each file starts with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Use `command = plan`. Nothing here talks to AWS, so tests run in seconds and in CI without credentials.
- Validations are tested with `expect_failures`. Point it at the object that carries the check: `[var.ingress_rules]` for a variable validation, `[aws_security_group.this]` for the `vpc_id` precondition. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so a null-guarded validation must be a conditional expression (`rule.from_port == null ? true : ...`), not `rule.from_port != null && ...`. This applies to validations, preconditions, and test assertions alike.
- The immutable-`description` replacement behaviour is visible at plan time as a `# forces replacement` annotation; assert on `plan_state` or the presence of a replacement plan with `command = plan`, no `apply` needed.
- `run` blocks in one `.tftest.hcl` file share state, so a run using `command = apply` leaks into later `plan` runs in the same file. If a future test ever needs `apply`, isolate it into its own file.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

The module has no submodules; it is deliberately one file per concern, and there are only three: `variables.tf`, `main.tf`, `outputs.tf`.

| Concern | Lives in |
| --- | --- |
| A new rule field or a new validation on `ingress_rules` / `egress_rules` | `variables.tf`, applied identically to both maps (they share one shape); a positive test in `tests/rules.tftest.hcl` and an `expect_failures` run in `tests/validation.tftest.hcl`. |
| Group-level behaviour (`create`, `name`, `description`, `vpc_id`, `tags`) | `variables.tf` for the input, `main.tf` for the precondition or rendering, a test in `tests/defaults.tftest.hcl`. |
| An advisory posture check (see `docs/DESIGN.md`'s "Deferred to v2") | A new `checks.tf`, with the same pattern `aws.modules.acm` and `aws.modules.alb` use: a `check` block with `assert`, a warning message, and a test that trips it with `expect_failures = [check.<name>]`. |
| Outputs | `outputs.tf`; every output has a description, and one derived from inputs is asserted in a test. |

Rules that apply everywhere: no data sources (the module never looks up a VPC's CIDR, an AMI, or anything else — the caller supplies whatever a rule needs), every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, and defaults are the secure choice.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the file or concern the change touches.

```text
feat(main): add an advisory check for public ingress without a description
fix(variables): reject a port range where from_port exceeds to_port
docs: explain the vpc-endpoint-style example
test(validation): cover self combined with another source
feat!: rename ingress_rules to ingress
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in an upgrade guide, and — because this module's whole purpose is to be called identically from three sibling repositories — a note on how the change affects `docs/CONSUMERS.md`.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] No data sources added to the module.
- [ ] Breaking changes documented in an upgrade guide, and `docs/CONSUMERS.md` updated if they affect the interface the three consumers depend on.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.security-group vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies the signed tag, formatting, validation, tests, and generated docs, then publishes the GitHub release. Never dispatch it from `main`: the workflow checks that the tag points at the revision it checked out.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
