# Design: aws.modules.security-group v1

Status: accepted 2026-09-27.

## Purpose

`aws.modules.security-group` provisions **one** AWS VPC security group and
its rules per module call: the group itself (`aws_security_group.this`), and
every ingress and egress rule as its own standalone resource
(`aws_vpc_security_group_ingress_rule.this`,
`aws_vpc_security_group_egress_rule.this`). It is deliberately narrow: one
group, its rules, nothing else. It does not create the thing the group is
attached to (an ECS service, a set of interface endpoints, a load balancer),
does not look up a VPC's CIDR block or any other attribute (the caller
supplies whatever a rule needs, such as a CIDR or a prefix list ID), and
performs no data-source reads.

## This is an extraction, not a new design

This module did not start here. `hatan4ik/aws.modules.ecs-service` v1.0.0
ships `modules/security-group` as an internal submodule: one security group
plus standalone ingress/egress rule resources, covered by 11 mock-provider
tests, that the root ECS service module calls for its task security group.
The interface was already correct: exactly-one-source validation on every
rule, a port-range rule that handles the all-protocols (`-1`) case, a `self`
shorthand for same-group traffic, and a `create` flag that turns the whole
module into a no-op. It did not need a redesign; it needed a home of its own,
because the same shape was quietly being reimplemented, slightly differently,
in every module that needed a security group:

| Repository | What it hand-rolls today | Resources duplicated |
| --- | --- | --- |
| `aws.modules.ecs-service` | `modules/security-group` (the source of this extraction) | `aws_security_group.this` (by `count`), `aws_vpc_security_group_ingress_rule.this`, `aws_vpc_security_group_egress_rule.this`, all `for_each`-keyed. |
| `aws.modules.vpc` (`modules/endpoints`) | An inline security group for interface endpoints: HTTPS from a list of VPC CIDRs, no egress. | `aws_security_group.this[0]`, `aws_vpc_security_group_ingress_rule.https` (`for_each` keyed by CIDR index). |
| `aws.modules.alb` | An inline security group for the ALB's listeners: one ingress rule per (listener port, CIDR) pair, one egress rule scoped to the VPC CIDR. | `aws_security_group.this` (singleton, `create_before_destroy`), `aws_vpc_security_group_ingress_rule.listener` (`for_each`), `aws_vpc_security_group_egress_rule.vpc` (singleton). |

Three independent copies of the same primitive is worse than one shared
module for reasons that show up the moment any one of them needs a fix:

- **Drift.** Each inline copy can silently diverge on validation strictness,
  tagging, or the exactly-one-source rule. `aws.modules.alb`'s egress rule,
  for example, is a fixed VPC-CIDR-only rule with no way to add a second
  egress destination without editing `security_group.tf`; this module's
  `egress_rules` map already supports that with no code change.
- **Test cost.** Three call sites mean three sets of security-group tests to
  maintain (or, as was actually the case, one well-tested copy in
  `ecs-service` and two untested inline copies). One module means one set of
  tests — deepened well beyond the 11 inherited here — that every consumer
  inherits for free.
- **Review surface.** "Does this security group correctly enforce exactly one
  source per rule" is a question worth answering once, by reviewers who own
  network policy, not three times by whoever happens to touch
  `alb.tf` or `modules/endpoints/main.tf` next.

`docs/CONSUMERS.md` works out exactly what changes in each of the three
repositories to adopt this module, including the `moved` blocks the two
inline copies need. A separate step performs those migrations; this repository
only had to prove the shared module can express what all three already do,
which is why two of the five examples below (`vpc-endpoint-style`,
`alb-style`) exist.

## What was preserved exactly, and why

Per the brief that produced this repository, the interface is copied
byte-for-byte from `aws.modules.ecs-service`'s `modules/security-group`:
variable names, types, defaults, and validation logic; resource labels;
output names. This was a deliberate constraint, not an oversight, because an
interface change here would break the migration before it starts. Two
specific choices that a from-scratch design would likely make differently,
kept as-is:

- **`description`'s default is `"ECS task security group"`.** This reads
  oddly for a module now used by ALBs and VPC endpoints, but every caller
  that reaches v1.0.0 either sets its own `description` (all five examples
  do) or is `aws.modules.ecs-service` itself, which already relies on this
  exact default. Changing a default is an interface change; see "Deferred to
  v2" below.
- **No `checks.tf`.** Other v1 modules in this session (`aws.modules.acm`,
  `aws.modules.alb`) add advisory `check` blocks for posture that is valid
  but usually unintended. A `public_ingress_without_description` or
  `wide_port_range` check would fit this module's shape well, but adding one
  is new behaviour, not extraction, so it is deferred rather than added
  silently.

## What changed in 1.1.0

`create_before_destroy_group` (default `false`) was added after the user
chose, when reviewing `docs/CONSUMERS.md`'s finding that migrating
`aws.modules.alb` onto this module would silently drop the
`create_before_destroy` guard ALB's own inline security group has today, to
add the guard here rather than accept the regression or leave ALB
unmigrated. It is purely additive: the default path is byte-identical to
1.0.0 (same resource label, `aws_security_group.this[0]`, same plan for
every existing caller), so this ships as a minor version with no interface
break. See `main.tf`'s header comment for why it needed a second, mutually
exclusive resource instead of a variable inside the existing one's
`lifecycle` block — Terraform requires `lifecycle` arguments to be literal
values. `docs/CONSUMERS.md`'s ALB section is updated accordingly: ALB's
migration should set `create_before_destroy_group = true` to keep its
current guarantee exactly.

## What changed in 1.2.0

1.1.0's `aws_security_group.this_cbd` kept the fixed `name = var.name`.
Security-group names are unique per VPC, and `create_before_destroy` creates
the replacement while the old group still exists, so the replacement a
`description` change forces (the headline case the feature exists for) was
rejected by AWS with `InvalidGroup.Duplicate`. The failure was safe (the old
group survived, the apply errored), but the "no window without a group"
guarantee only held when `name` or `vpc_id` also changed in the same update.

`this_cbd` now sets `name_prefix = "${var.name}-"` instead of `name`, the same
way the AWS provider itself solves this: each generation gets an AWS-generated
name (the prefix plus a 26-character unique suffix), so old and new never
collide. The `Name` tag stays `var.name`. Because the provider caps
`name_prefix` at 229 characters, a precondition on `this_cbd` limits `name` to
228 characters on that path only. The default path (`aws_security_group.this`,
`create_before_destroy_group = false`) is untouched and still uses
`name = var.name`, so this is a minor release for every default caller. For a
caller that already opted in, it is a behaviour change: the group's `name`
attribute changes from exactly `var.name` to a generated value, which
replaces the group once (create-before-destroy, so without a gap) on the
first apply after upgrading. See `CHANGELOG.md` for the exact upgrade note.

mock_provider cannot reproduce a ForceNew replacement or AWS's per-VPC name
uniqueness, so the contract tests pin the naming contract and
`tests/integration/create_before_destroy_group.tftest.hcl` proves the real
description-only replacement against the API.

1.2.0 also adds three validations that only reject values AWS rejects anyway
(a reserved `aws:` tag-key prefix, an unrecognised `ip_protocol`, an ICMP type
or code above 255) and loosens two that rejected valid configurations (ICMP
type/code no longer need `from_port <= to_port`, so type 8 code 0 is
accepted; protocol numbers other than tcp, udp, and icmp may omit ports).

## Deferred to v2

Recorded here instead of implemented, so the interface stays exactly what
`aws.modules.ecs-service` shipped and what `docs/CONSUMERS.md` promises the
three consumers:

- **Advisory `check` blocks.** A `public_ingress_without_description` check
  (warn when a rule's `cidr_ipv4` is `0.0.0.0/0` or `cidr_ipv6` is `::/0` and
  `description` is null) and a `wide_port_range` check (warn when
  `to_port - from_port` exceeds some threshold) would match the posture-check
  pattern used by `aws.modules.acm` and `aws.modules.alb`. Neither changes a
  resource, a variable, or an output, so either could ship as a minor (1.1.0)
  release without touching consumers.
- **A friendlier `description` default.** Something like `"Managed by
  aws.modules.security-group"` reads better once this module is not only
  called from inside `ecs-service`. This is a breaking change (`description`
  is immutable on `aws_security_group`, so changing its *default* only
  matters for a caller that never set it explicitly, but it is still a
  behaviour change worth a major version and an upgrade note) and is out of
  scope for a v1.0.0 that must stay byte-for-byte compatible with the source
  submodule.
- **IPv6 CIDR validation.** `cidr_ipv4` and `cidr_ipv6` are accepted as plain
  strings with no `can(cidrhost(...))`-style format check, exactly as in the
  source submodule. Real format validation is a genuine improvement but is an
  interface tightening (a value that plans today could fail validation
  tomorrow), so it waits for a major version.
- **A `security_group_rule_ids` combined output** (ingress and egress merged
  into one map) was considered while writing `examples/alb-style`, where a
  caller often wants "every rule ID" for a single audit output. The two
  separate outputs (`ingress_rule_ids`, `egress_rule_ids`) already cover it
  with a `merge()` at the call site, so a combined output is a convenience,
  not a gap.

## Principles and how the module applies them

- **Single responsibility.** One security group, its rules, nothing else.
  The module does not create, look up, or attach the thing the group secures.
- **Open/closed.** New rules arrive as data: another key in `ingress_rules`
  or `egress_rules`. No behaviour requires editing the module.
- **Liskov substitution.** `id` and `arn` mean the same thing whether the
  module models an ECS task's group, an ALB's listener group, or a VPC
  endpoint's group: the identifier of a security group a caller can attach.
- **Interface segregation.** A caller who wants no rules at all still gets a
  group (`ingress_rules` and `egress_rules` default to `{}`); a caller who
  wants no group at all sets `create = false` and reads `null` back.
- **Dependency inversion.** The module depends on identifiers the caller
  already has (a VPC ID, a peer security group ID, a prefix list ID), never
  on how they were produced, and performs no data-source reads. When a caller
  needs the VPC's CIDR block for an egress rule (as `aws.modules.alb` does
  today), that lookup stays at the call site — seen in
  `examples/alb-style`, which keeps its own `data.aws_vpc.this` for exactly
  that reason.
- **Clean, deterministic code.** Every rule is a standalone resource keyed by
  a stable identifier the caller chooses, so adding, changing, or removing
  one rule never disturbs another or the group itself.

## Architecture

```text
root (one security group)
├── variables.tf   create, name, description, vpc_id, ingress_rules, egress_rules, tags.
├── main.tf        aws_security_group.this[0], aws_vpc_security_group_ingress_rule.this, aws_vpc_security_group_egress_rule.this.
└── outputs.tf      id, arn, ingress_rule_ids, egress_rule_ids.
```

Rule shape (identical for `ingress_rules` and `egress_rules`): a map keyed by
a stable identifier, valued with `description`, `from_port`, `to_port`,
`ip_protocol` (default `tcp`), and exactly one of `cidr_ipv4`, `cidr_ipv6`,
`prefix_list_id`, `referenced_security_group_id`, or `self = true`. `self`
sets `referenced_security_group_id` to the group's own ID once it exists, for
traffic between members of the same group (see `examples/self-referencing-cluster`).

## Security defaults

- No implicit egress. The AWS provider revokes the default allow-all egress
  rule when it creates a VPC security group, so a group with an empty
  `egress_rules` map cannot reach anything, including its own dependencies
  (image pulls, DNS). This is a deliberate secure default inherited from the
  source submodule, not a gap: `examples/disabled` and every other example
  that expects network access declares its own egress.
- Exactly one source or destination per rule, enforced at plan time. A rule
  that names two of `cidr_ipv4` / `cidr_ipv6` / `prefix_list_id` /
  `referenced_security_group_id`, or names zero, fails validation before any
  API call.
- No data sources, no wildcard IAM (this module creates no IAM resources at
  all), and no default that widens access beyond what the caller declares.

## Testing strategy

- Contract tests use `mock_provider "aws" {}` with `command = plan`; no
  credentials. Beyond the 11 runs inherited from the source submodule,
  `tests/` adds a dedicated failing case for every validation branch (the
  exactly-one-source rule for both ingress and egress independently, the
  port-range rule for both directions, an all-protocol rule that still sets
  one of the two ports, `self` combined with another source), the `self`
  special case's positive behaviour, and the `create = false` no-op path in
  isolation.
- The immutable-`description`-replaces-the-group behaviour (README,
  "Description replaces the group") was investigated for a dedicated test
  and deliberately **not** added, based on an empirical finding made while
  building this repository, not an assumption: `mock_provider "aws" {}`
  does not encode a resource's `ForceNew` fields (the public
  `terraform providers schema -json` output does not expose them either;
  they live only in the provider's internal diff logic), so an
  apply-then-plan test that changes `description` against `mock_provider`
  plans an in-place update (`# aws_security_group.this[0] will be updated
  in-place`) where the real AWS provider requires replacement. A test that
  asserted replacement under `mock_provider` would assert something false
  about this module's actual behaviour against the real API, which is worse
  than asserting nothing, so none was added. The behaviour itself is real
  (AWS has no API to update a security group's description) and stays
  documented in the README as an inherited, production-relied-upon
  guarantee (`aws.modules.ecs-service` already depends on it) rather than a
  tested one; `tests/integration/smoke.tftest.hcl` does not cover it either,
  since a smoke suite applies once and tears down without re-planning a
  change.
- One case genuinely needs `command = apply`: `self = true`'s resolved
  `referenced_security_group_id` can only be compared against the group's
  own `id` once both are known, and computed attributes are unknown under
  `mock_provider` at plan time (the same finding as above, applied to `id`
  instead of `description`). `tests/self_reference.tftest.hcl` isolates this
  single apply-based run into its own file per the common brief's
  `run`-block-state-sharing gotcha, so it cannot leak state into any
  `command = plan` run elsewhere in `tests/`.
- `tests/integration/smoke.tftest.hcl` applies a real group with one ingress
  and one egress rule against a disposable VPC fixture
  (`tests/integration/setup`) and destroys everything afterward. It is
  dispatch-only and never runs in the credential-free quality pipeline.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0`.
- AWS provider `>= 6.35.0, < 7.0.0`.
- No submodules; the whole module is the root.

## Migration

`docs/CONSUMERS.md` is the migration note this module exists to enable: what
changes in `aws.modules.ecs-service` (a one-line `source` change, no `moved`
blocks — explained there), and the exact `moved` block HCL
`aws.modules.vpc`'s `modules/endpoints` and `aws.modules.alb` each need to
adopt this module in place of their inline security-group resources. This
repository does not make those changes; a separate step does, informed by
that document.
