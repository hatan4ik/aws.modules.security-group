# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

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

[Unreleased]: https://github.com/hatan4ik/aws.modules.security-group/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.security-group/releases/tag/v1.0.0
