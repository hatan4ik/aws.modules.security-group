# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

## [1.2.0] - 2026-10-02

### Fixed

- **`create_before_destroy_group = true` now survives the replacement it exists for.** In 1.1.0, `aws_security_group.this_cbd` combined `lifecycle.create_before_destroy` with the fixed `name = var.name`. Security-group names are unique per VPC, so a description-only change made Terraform create the replacement first, under the same name, in the same VPC, and AWS rejected it with `InvalidGroup.Duplicate` (safe: the old group survived and the apply failed, but the "no window without a group" guarantee was not delivered). `this_cbd` now sets `name_prefix = "${var.name}-"` and no `name`, so every generation gets a unique AWS-generated name and the replacement is created before the old group is destroyed.
- ICMP rules: `from_port`/`to_port` are ICMP type and code, not a range, so the `from_port <= to_port` check no longer applies to `icmp`/`icmpv6`/`1`/`58` (type 8 code 0, echo request, was wrongly rejected).
- Rules for protocol numbers other than tcp, udp, and icmp (for example `50`, ESP) may now omit `from_port`/`to_port`, which AWS ignores for them. Rules that set both keep the 1.1.0 range check.
- `create_before_destroy_group`'s description now says accurately what flipping it does: a caller-side `moved` block between `aws_security_group.this[0]` and `this_cbd[0]` carries the state across, but the group is still replaced once because the two variants name it differently (create-before-destroy when turning it on, destroy-then-create when turning it off); neither direction collides on the name.

### Changed

- **Behaviour change on the `create_before_destroy_group = true` path only (currently `aws.modules.alb`).** The CBD-path security group's `name` attribute changes from the fixed value `var.name` (for example `orders-alb`) to an AWS-generated name starting with the same prefix plus a hyphen: `"${var.name}-"` followed by a 26-character unique suffix (for example `orders-alb-20261002093015123400000001`). Its `name_prefix` attribute is `"${var.name}-"`. The `Name` tag is unchanged (`var.name`). Upgrade impact for a caller already applied on 1.1.0 with the flag on, and for a `moved` block from any fixed-name group into `this_cbd[0]`: the first plan shows one replacement of `aws_security_group.this_cbd[0]` (`name_prefix` forces it), performed create-before-destroy, so the group ID changes, its rules are re-created on the new group, and anything referencing `id`/`arn` (for example a load balancer's `security_groups`) is updated to the new ID before the old group is deleted. Anything outside the caller's configuration that references the old group ID will block that deletion. Do not compare the group's `name` against `var.name`; use the `Name` tag or the `id` output.
- `name` is limited to 228 characters when `create_before_destroy_group = true` (a precondition on `aws_security_group.this_cbd`): the provider caps `name_prefix` at 229 characters (255 minus its 26-character suffix). The default path keeps the 255-character limit.
- The default path (`create_before_destroy_group = false`, `aws_security_group.this`) is byte-identical to 1.1.0: same resource address, same `name = var.name`, no plan change for any default caller.

### Added

- Validation: `tags` keys must not start with the reserved `aws:` prefix (any letter case), matching `aws.modules.state`; `ip_protocol` must be `tcp`, `udp`, `icmp`, `icmpv6`, `-1`, or a protocol number `0`-`255`; ICMP type and code must each be `-1` to `255`. Each only rejects values AWS rejects at apply anyway.
- Tests: plan-mode assertions on the CBD path's `name_prefix`, the default path's fixed name, and the 228-character cap; `tests/create_before_destroy_group_description_change.tftest.hcl` (apply, mock) for a description-only change on the CBD path; the real-API integration suite `tests/integration/create_before_destroy_group.tftest.hcl` (`make integration-create_before_destroy_group`, also selectable in the `integration` workflow) proving the replacement gets a new group ID without a name collision; validation cases for every new branch.

## [1.1.0] - 2026-09-29

### Added

- `create_before_destroy_group` (default `false`, preserving all existing behavior): when `true`, the security group is created with `lifecycle.create_before_destroy`, so a forced replacement (for example, a `description` change, which is immutable on `aws_security_group`) creates the new group before destroying the old one, avoiding a window with no security group at all. Implemented as a second, mutually exclusive resource (`aws_security_group.this_cbd`) rather than a variable inside `aws_security_group.this`'s own `lifecycle` block, because Terraform requires `lifecycle` arguments to be literal values, never a variable or expression. `id`, `arn`, and every ingress/egress rule resolve to whichever of the two resources is active, via `local.security_group_id`/`local.security_group_arn`; no existing caller's resource address or plan changes, since the default path still produces `aws_security_group.this[0]` exactly as before. Added to support `aws.modules.alb`'s planned migration onto this module without losing the `create_before_destroy` guard its own inline security group has today.

## [1.0.0] - 2026-09-27

Initial release. Extracted from `hatan4ik/aws.modules.ecs-service`'s internal `modules/security-group` submodule (interface unchanged: same variable names, types, defaults, and validations; same resource labels; same outputs) and promoted to its own module so the security-group primitive that `aws.modules.ecs-service`, `aws.modules.vpc`'s `modules/endpoints`, and `aws.modules.alb` each currently duplicate can be maintained, tested, and versioned once. See [docs/DESIGN.md](docs/DESIGN.md) for why, and [docs/CONSUMERS.md](docs/CONSUMERS.md) for the exact migration each of the three consumers needs, including the `moved` block HCL for the two that hand-roll their own security-group resources today.

### Added

- `aws_security_group.this`: one security group per module call, gated by `create`, with an immutable `description` (changing it replaces the group) and a `vpc_id` precondition.
- `aws_vpc_security_group_ingress_rule.this` and `aws_vpc_security_group_egress_rule.this`: every rule in `ingress_rules` / `egress_rules` as its own standalone resource, keyed by a stable identifier, each declaring exactly one of `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, or `self = true`.
- Plan-time validation: exactly one source/destination per rule; a protocol-specific rule needs `from_port`/`to_port` in range with `from_port <= to_port`, an all-protocol (`-1`) rule must set neither.
- Outputs `id`, `arn`, `ingress_rule_ids`, `egress_rule_ids`.
- `create = false`: no resources, `id`/`arn` are null, rule maps are ignored.
- Mock-provider contract tests in `tests/` covering the 11 behaviours inherited from the source submodule plus a dedicated failing case for every validation branch, the `self` special case, and the `create = false` path in isolation.
- Five examples: `minimal`, `self-referencing-cluster`, `vpc-endpoint-style`, `alb-style`, `disabled`. The last two specifically reproduce, with this module, the security-group shapes that `aws.modules.vpc`'s `modules/endpoints` and `aws.modules.alb` currently hand-roll.
- Credential-driven integration suite `smoke` in `tests/integration/` against a disposable VPC fixture (`tests/integration/setup`), a `make integration-smoke` target, a dispatch-only `integration` workflow that assumes a role through GitHub OIDC from the protected `integration` environment, and the IAM trust and permissions documents the role needs.
- `docs/DESIGN.md` (the extraction rationale and what was deliberately deferred to v2), `docs/CONSUMERS.md` (migration mechanics and `moved` blocks for the three consumers), `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE` (Apache-2.0), the `Makefile` quality gate, pre-commit, tflint, checkov, trivy, and terraform-docs configuration, Dependabot, issue and pull request templates, and the `module-release` workflow.

[Unreleased]: https://github.com/hatan4ik/aws.modules.security-group/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/hatan4ik/aws.modules.security-group/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/hatan4ik/aws.modules.security-group/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/hatan4ik/aws.modules.security-group/releases/tag/v1.0.0
