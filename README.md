# aws.modules.security-group

Provisions one AWS VPC security group and its rules per module call: the group itself, and every ingress and egress rule as its own standalone resource so a caller can add, change, or remove one rule without disturbing the others. It creates nothing beyond the group and its rules, performs no data-source reads, and starts with no egress at all — the AWS provider revokes the default allow-all egress rule when it creates a security group, so a group with no declared `egress_rules` cannot reach anything until you say so. Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

This module is an **extraction**, not a new design: it is `hatan4ik/aws.modules.ecs-service`'s internal `modules/security-group` submodule, promoted to its own repository, interface unchanged, so that `aws.modules.ecs-service`, `aws.modules.vpc`'s `modules/endpoints`, and `aws.modules.alb` — which today each hand-roll a slightly different version of the same primitive — can share one tested, versioned module instead. See [docs/DESIGN.md](docs/DESIGN.md) for why, and [docs/CONSUMERS.md](docs/CONSUMERS.md) for exactly what each of the three needs to change, including the `moved` block HCL for the two that currently inline their own resources.

## Why this module

What you get from `name` and `vpc_id`, without setting anything else beyond the rules you need:

- Every rule is its own resource. `aws_vpc_security_group_ingress_rule.this["<key>"]` and `aws_vpc_security_group_egress_rule.this["<key>"]`, keyed by the identifier you choose in `ingress_rules` / `egress_rules`. Renaming a key replaces that rule only; nothing else in the group is disturbed.
- Exactly one source or destination per rule, checked at plan time. Each rule names exactly one of `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, or `self = true`. A rule with zero or two of these fails validation before any API call, with a message that says so.
- `self` for same-group traffic. `self = true` sets `referenced_security_group_id` to the group's own ID once it exists — the shape a clustered service uses for gossip or replication between its own members (`examples/self-referencing-cluster`).
- No implicit egress. Declare `egress_rules` or the group cannot pull images, resolve DNS, or reach any dependency. This is deliberate, not an oversight: an empty `egress_rules` map is a secure default, not a bug.
- Ports validated by protocol. `ip_protocol` defaults to `tcp`. A protocol-specific rule needs both `from_port` and `to_port` (`-1` to `65535`, `from_port <= to_port`); an all-protocol rule (`ip_protocol = "-1"`) must set neither.
- `create = false` is a real no-op. Nothing is created, `id` and `arn` are `null`, and the rule maps are ignored — useful when a caller's own flag decides whether it manages its own security group at all (see `examples/disabled`, and how `aws.modules.vpc`'s `modules/endpoints` uses the equivalent `create_security_group` flag today).

## Quick start

```hcl
module "security_group" {
  source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=<commit-sha>" # v1.0.0

  name        = "orders-api"
  description = "Tasks of ECS service orders-api"
  vpc_id      = "vpc-0123456789abcdef0"

  ingress_rules = {
    from_alb = { description = "HTTP from the load balancer", from_port = 8080, to_port = 8080, referenced_security_group_id = "sg-0aaaaaaaaaaaaaaaa" }
  }

  egress_rules = {
    vpc_tls = { description = "TLS to VPC endpoints", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
    s3_tls  = { description = "TLS to the S3 gateway endpoint", from_port = 443, to_port = 443, prefix_list_id = "pl-0123456789abcdef0" }
    dns     = { from_port = 53, to_port = 53, ip_protocol = "udp", cidr_ipv4 = "10.0.0.2/32" }
  }

  tags = { Environment = "prod" }
}
```

This creates one security group named `orders-api`, one ingress rule from a peer security group, and three egress rules (VPC-scoped HTTPS, an S3 gateway prefix list, and DNS), each a standalone resource keyed by its map key and tagged `Name = orders-api-<key>`.

## Architecture

```text
root (one security group)
├── variables.tf   create, name, description, vpc_id, ingress_rules, egress_rules, tags, create_before_destroy_group
├── main.tf        aws_security_group.this[0] (default) or aws_security_group.this_cbd[0] (create_before_destroy_group = true),
│                  aws_vpc_security_group_ingress_rule.this, aws_vpc_security_group_egress_rule.this
└── outputs.tf     id, arn, ingress_rule_ids, egress_rule_ids
```

`ingress_rules` and `egress_rules` share one shape: a map keyed by a stable identifier you choose, valued with `description` (optional), `from_port` / `to_port` (required together for `tcp`/`udp` and, as ICMP type and code, for `icmp`/`icmpv6`; omitted for `-1`; optional for any other protocol number), `ip_protocol` (default `tcp`; `tcp`, `udp`, `icmp`, `icmpv6`, `-1`, or a protocol number `0`-`255`), and exactly one of `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, or `self` (default `false`).

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | One ingress rule, one egress rule: the smallest working call. |
| [`examples/self-referencing-cluster`](examples/self-referencing-cluster) | `self = true` for a clustered service's gossip port, alongside an ALB-sourced ingress rule and VPC-scoped egress. |
| [`examples/vpc-endpoint-style`](examples/vpc-endpoint-style) | A single HTTPS-from-CIDR ingress rule and no egress — the exact shape `aws.modules.vpc`'s `modules/endpoints` hand-rolls today, proving this module can replace it. |
| [`examples/alb-style`](examples/alb-style) | Multiple listener-port ingress rules (HTTP and HTTPS from public CIDRs) plus a VPC-CIDR-scoped egress rule — the exact shape `aws.modules.alb` hand-rolls today, proving this module can replace it. |
| [`examples/disabled`](examples/disabled) | `create = false`: no resources, null outputs. |

## Security model

- No implicit egress. The AWS provider revokes the default allow-all egress rule when it creates a security group; this module adds no rule the caller did not declare in `egress_rules`.
- Exactly one source or destination per rule, and a validated port range, both enforced before any API call — never discovered at apply time.
- No data sources and no IAM resources. The module never looks up a VPC's CIDR block, an AMI, or an availability zone; every value a rule needs (a CIDR, a prefix list ID, a peer security group ID) is supplied by the caller. When a caller needs to derive one of those (as `aws.modules.alb` derives its egress CIDR from the VPC itself), that lookup stays at the call site — see `examples/alb-style`.
- `description` is immutable on `aws_security_group` and changing it destroys and recreates the group and every rule; keep it stable once a real service depends on the group's ID. By default the old group is destroyed first. With `create_before_destroy_group = true` the replacement is created first, and so that it can coexist with the old group in the same VPC its name is generated by AWS from `name_prefix = "<name>-"` (since 1.2.0; see [CHANGELOG.md](CHANGELOG.md)). The `Name` tag is `var.name` either way.
- The module adds only a `Name` tag (`var.name` on the group, `"${var.name}-<key>"` on each rule) and never overrides a caller tag.

## Testing

Two layers, deliberately separate:

- **Contract tests** (`tests/`, run by `make test` and by CI) use `mock_provider`: no credentials, nothing created, placeholder VPC and security group IDs. They cover the group and rule rendering, tagging, `create = false`, the `self` special case, and every validation branch through `expect_failures`.
- **Integration suite** (`tests/integration/`, run by `make integration-smoke`, `make integration-create_before_destroy_group`, or the dispatch-only `integration` workflow) applies the module for real in **your** account against a disposable VPC fixture it creates and destroys itself. See [tests/integration/README.md](tests/integration/README.md) for permissions and the GitHub environment contract.

## Design principles

- Single responsibility. The module owns one security group and its rules, nothing else.
- Open/closed. New rules arrive as data — another key in `ingress_rules` or `egress_rules` — with no module code to edit.
- Liskov substitution. `id` and `arn` mean the same thing whether the group secures an ECS task, an ALB, or a set of VPC endpoints.
- Interface segregation. A caller who wants no rules still gets a group; a caller who wants no group sets `create = false`.
- Dependency inversion. The module depends on identifiers the caller already has, never on how they were produced, and performs no data-source reads.

The full rationale, the three call sites this module is meant to unify, and what was deliberately deferred to a future version, are in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- One security group and its rules per module call. No submodules.
- Nothing in the v1 interface is scheduled to change; it is intentionally frozen so three sibling repositories can adopt it without a resource-address surprise (see [docs/CONSUMERS.md](docs/CONSUMERS.md)). Additions arrive as optional inputs and outputs, never as a rename.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you:

```hcl
module "security_group" {
  source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag points at the revision it checked out.

All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.this_cbd](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_create"></a> [create](#input\_create) | Create the security group and its rules. When false the module creates nothing and outputs null identifiers. | `bool` | `true` | no |
| <a name="input_create_before_destroy_group"></a> [create\_before\_destroy\_group](#input\_create\_before\_destroy\_group) | When true, the security group is managed by aws\_security\_group.this\_cbd, which has lifecycle.create\_before\_destroy and is named by AWS from name\_prefix = "<name>-" plus a unique suffix (the Name tag stays name). A forced replacement (for example a description change, which is immutable on aws\_security\_group) then creates the new group, under a new unique name, before destroying the old one, so there is no window without a security group. Default false keeps the original resource, aws\_security\_group.this, with the fixed name = name. Flipping this on an existing group switches which of the two resources manages it. A caller-side moved block between module.<call>.aws\_security\_group.this[0] and module.<call>.aws\_security\_group.this\_cbd[0] carries the state across, but the group is still replaced once because the two variants name it differently (fixed name versus name\_prefix): create-before-destroy when turning it on, destroy-then-create when turning it off. Without a moved block Terraform destroys one resource and creates the other with no ordering guarantee between them. Neither direction collides on the group name, since exactly one side always uses a generated name. Set it once, at adoption, not as an ongoing toggle. | `bool` | `false` | no |
| <a name="input_description"></a> [description](#input\_description) | Security group description. Changing it replaces the group. | `string` | `"ECS task security group"` | no |
| <a name="input_egress_rules"></a> [egress\_rules](#input\_egress\_rules) | Egress rules keyed by a stable identifier, same shape as ingress\_rules. A group with no egress rules cannot pull images or reach any dependency. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_ingress_rules"></a> [ingress\_rules](#input\_ingress\_rules) | Ingress rules keyed by a stable identifier. Each rule names exactly one source: cidr\_ipv4, cidr\_ipv6, prefix\_list\_id, referenced\_security\_group\_id, or self. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Security group name. Must be unique within the VPC. Also the group's Name tag. When create\_before\_destroy\_group is true the group's name is instead generated by AWS from name\_prefix = "<name>-" plus a unique suffix, so name must then be at most 228 characters. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the security group and every rule. Keys must not use the AWS-reserved aws: prefix. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the security group belongs to. Required when create is true. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | Security group ARN, or null when create is false. |
| <a name="output_egress_rule_ids"></a> [egress\_rule\_ids](#output\_egress\_rule\_ids) | Egress rule IDs keyed by rule key. |
| <a name="output_id"></a> [id](#output\_id) | Security group ID, or null when create is false. |
| <a name="output_ingress_rule_ids"></a> [ingress\_rule\_ids](#output\_ingress\_rule\_ids) | Ingress rule IDs keyed by rule key. |
<!-- END_TF_DOCS -->
