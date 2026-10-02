# Migration notes for the three consumers

This module exists to replace security-group code that is currently
duplicated, in three slightly different shapes, across
`hatan4ik/aws.modules.ecs-service`, `hatan4ik/aws.modules.vpc`
(`modules/endpoints`), and `hatan4ik/aws.modules.alb`. This repository does
not make any of those three changes — each consumer's migration is a
separate step in its own repository — but the mechanics below were worked
out against the real source of each repository (read-only) while the
interface was fresh, so that step can be executed directly rather than
re-derived.

Every example below assumes the consumer pins this module at the commit SHA
this repository's v1.0.0 release lands on (see this repository's
`CHANGELOG.md` and README for the exact `ref=`).

## `aws.modules.ecs-service`: no `moved` blocks needed

Today, `aws.modules.ecs-service`'s root module calls its own internal
submodule:

```hcl
module "security_group" {
  source = "./modules/security-group"

  name        = var.name
  description = "Tasks of ECS service ${var.name}"
  vpc_id      = var.vpc_id
  create      = var.create_security_group
  ...
}
```

The migration changes exactly one line — the `source` argument — and nothing
else:

```hcl
module "security_group" {
  source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=<this-release-commit>" # v1.0.0

  name        = var.name
  description = "Tasks of ECS service ${var.name}"
  vpc_id      = var.vpc_id
  create      = var.create_security_group
  ...
}
```

**Why this needs no `moved` blocks.** A Terraform resource address is
`module.<call label>.<resource type>.<resource name>[<key>]`. The module
call's own label — `security_group`, the name after the `module` keyword in
the consumer's HCL — is what appears in that address, never the module's
`source` argument. Terraform resolves `source` only to decide which
configuration to load for that call; it has no bearing on state addressing.
Since this extraction copied `aws.modules.ecs-service`'s
`modules/security-group` byte-for-byte — same resource labels
(`aws_security_group.this`, `aws_vpc_security_group_ingress_rule.this`,
`aws_vpc_security_group_egress_rule.this`), same variable names driving the
same `count`/`for_each` expressions — every resource this module creates
under `module.security_group` in the consumer's state has *exactly* the
address it already has today. `terraform plan` after the `source` change
shows no changes at all (besides the module now being fetched from a new
location on the next `init -upgrade`); it is provably a zero-diff change.
This is the same reasoning `aws.modules.acm`'s `docs/UPGRADE-1.0.md` uses for
its own unchanged resource addresses, applied here to a module boundary
instead of a version bump.

Local submodule note: after this migration, `aws.modules.ecs-service` may
optionally delete `modules/security-group/` from its own repository once the
`source` change is merged, since nothing local references it any longer. That
deletion is itself outside this document's scope.

## `aws.modules.vpc`'s `modules/endpoints`: needs `moved` blocks

Today (`modules/endpoints/main.tf`), the endpoints submodule hand-rolls its
own group:

```hcl
resource "aws_security_group" "this" {
  count = var.create_security_group ? 1 : 0

  name        = local.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = local.security_group_name })

  lifecycle {
    precondition {
      condition     = length(var.vpc_cidr_blocks) > 0
      error_message = "vpc_cidr_blocks must list at least one CIDR when create_security_group is true."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = { for index, cidr in var.vpc_cidr_blocks : tostring(index) => cidr if var.create_security_group }

  security_group_id = aws_security_group.this[0].id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value

  tags = merge(var.tags, { Name = "${local.security_group_name}-https-${each.key}" })
}
```

### The rewrite

```hcl
module "security_group" {
  source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=<this-release-commit>" # v1.0.0

  create      = var.create_security_group
  name        = local.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id

  # Key by the same tostring(index) used today, so the moved block below can
  # match instances by for_each key without a per-instance remap.
  ingress_rules = {
    for index, cidr in var.vpc_cidr_blocks : tostring(index) => {
      description = "HTTPS from the VPC"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = cidr
    }
  }

  tags = var.tags
}
```

`locals.security_group_ids` reads from the module's outputs instead of the
inline resource:

```hcl
locals {
  security_group_ids = concat(
    module.security_group.id != null ? [module.security_group.id] : [],
    sort(tolist(var.security_group_ids)),
  )
}
```

and every other reference to `aws_security_group.this[0].id` becomes
`module.security_group.id`.

### The `moved` blocks this migration needs

Both of the endpoints submodule's own resources move under the new module
call. The security group is a `count`-based singleton, so the move is
index-to-index; the ingress rule is `for_each`-keyed by `tostring(index)` on
both sides (unchanged key set), so one whole-resource `moved` block covers
every instance without listing each key:

```hcl
moved {
  from = aws_security_group.this[0]
  to   = module.security_group.aws_security_group.this[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.https
  to   = module.security_group.aws_vpc_security_group_ingress_rule.this
}
```

### Behavioural notes for whoever performs this migration

- **The precondition changes wording and trigger.** Today's precondition
  fires on `length(var.vpc_cidr_blocks) == 0` with the message
  `"vpc_cidr_blocks must list at least one CIDR when create_security_group is
  true."`. This module's own precondition is `var.vpc_id != null` (`"vpc_id
  is required when create is true."`). An endpoints caller who passes
  `create_security_group = true` with an empty `vpc_cidr_blocks` today gets a
  clear, endpoints-specific error at plan time; after migration they instead
  get a security group with zero ingress rules and no error at all (an empty
  `ingress_rules` map is valid input to this module). If that guarantee is
  worth keeping, the endpoints submodule needs its own precondition
  (elsewhere in `modules/endpoints/main.tf`, for example on
  `aws_vpc_endpoint.interface`, which already has a related precondition on
  `local.security_group_ids`) rather than relying on the called module to
  provide it — this module intentionally has no opinion on
  `vpc_cidr_blocks`, since that variable does not exist in its interface.
- **Tagging is unchanged.** Both the group and each rule keep the same
  `Name` tag shape (`local.security_group_name`,
  `"${local.security_group_name}-https-${each.key}"`) because this module
  derives the same tags from `name` and the rule key that the inline code
  computed by hand — `merge(var.tags, { Name = "${var.name}-${each.key}" })`
  in this module versus `merge(var.tags, { Name =
  "${local.security_group_name}-https-${each.key}" })` today are the same
  value once `name = local.security_group_name`. No tag-driven external
  system (cost allocation, tag-based access policies) observes a change.
- **The `count`-wrapped module call was deliberately avoided.** The rewrite
  above passes `create = var.create_security_group` straight through to the
  module instead of wrapping the `module "security_group"` block itself in
  `count`. This keeps the resource addresses index-stable
  (`module.security_group.aws_security_group.this[0]`, not
  `module.security_group[0].aws_security_group.this[0]`) and matches how
  `aws.modules.ecs-service` already calls this same module, but it is a
  choice the migration author should confirm still fits `modules/endpoints`'
  broader structure before applying it.

## `aws.modules.alb`: needs `moved` blocks

Today (`security_group.tf`), the ALB module hand-rolls its own group,
non-indexed, with `create_before_destroy`:

```hcl
data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Controls access to the ${var.name} ALB's listeners; egress is scoped to the VPC CIDR only."
  vpc_id      = var.vpc_id

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "listener" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "Allow inbound ${each.value.port} from ${each.value.cidr}."

  #checkov:skip=CKV_AWS_260:Public ALB by design (ADR-0004); web_acl_arn is optional and the public_without_waf check warns when it and 0.0.0.0/0 are combined.
}

resource "aws_vpc_security_group_egress_rule" "vpc" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic within the VPC only; no unrestricted egress."
}
```

`locals.tf`'s `ingress_rules` is already keyed usefully:

```hcl
ingress_rules = {
  for pair in setproduct(local.active_listener_ports, var.security_group_ingress_cidrs) :
  "${pair[0]}-${pair[1]}" => { port = tonumber(pair[0]), cidr = pair[1] }
}
```

### The rewrite

`data.aws_vpc.this` stays — this module performs no data-source reads by
design, so the CIDR lookup for the egress rule remains the caller's
responsibility, exactly as `docs/DESIGN.md`'s "Interface segregation" /
"Dependency inversion" sections describe and as `examples/alb-style`
demonstrates:

```hcl
data "aws_vpc" "this" {
  id = var.vpc_id
}

module "security_group" {
  source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=<this-release-commit>" # v1.2.0

  name                        = "${var.name}-alb"
  description                 = "Controls access to the ${var.name} ALB's listeners; egress is scoped to the VPC CIDR only."
  vpc_id                      = var.vpc_id
  create_before_destroy_group = true

  # Keys are unchanged from today's local.ingress_rules, so the moved block
  # below matches every instance by key with no remapping.
  ingress_rules = {
    for key, rule in local.ingress_rules : key => {
      description = "Allow inbound ${rule.port} from ${rule.cidr}."
      from_port   = rule.port
      to_port     = rule.port
      ip_protocol = "tcp"
      cidr_ipv4   = rule.cidr
    }
  }

  egress_rules = {
    vpc = {
      description = "Allow all outbound traffic within the VPC only; no unrestricted egress."
      ip_protocol = "-1"
      cidr_ipv4   = data.aws_vpc.this.cidr_block
    }
  }

  tags = local.tags
}
```

`outputs.tf`'s `security_group_id` (or equivalent) becomes
`module.security_group.id`, and the
`#checkov:skip=CKV_AWS_260` comment on the public listener rule moves with it
— it now belongs on the `ingress_rules` map entry's rendering inside this
module's own `main.tf`. It already carries an equivalent, more general
`checkov:skip=CKV2_AWS_5` on `aws_security_group.this` (attachment cannot be
graph-followed through a module boundary); `CKV_AWS_260` (public ingress on
port 80/443) is a **finding specific to ALB's own use** of this module, not a
property of the module itself, so the migration should re-add the
`#checkov:skip=CKV_AWS_260` at the ALB repository's own scan configuration
(`.checkov.yml`, `skip-check`, scoped to the ALB module's directory) rather
than trying to carry an inline comment through a module boundary, since
Checkov attributes an inline `checkov:skip` comment to the resource block it
is physically adjacent to, and that block now lives in a different
repository.

### The `moved` blocks this migration needs

The security group moves from a non-indexed singleton to this module's
`count`-based `[0]` instance — `this_cbd[0]`, not `this[0]`, because the
rewrite sets `create_before_destroy_group = true` to preserve ALB's existing
`create_before_destroy` guarantee (see the behavioural note above); the
ingress rule is `for_each`-keyed on both sides with an unchanged key set, so
one whole-resource `moved` block covers it; the egress rule moves from a
non-indexed singleton to a specific `for_each` key (`"vpc"`) in this module's
`egress_rules` map:

```hcl
moved {
  from = aws_security_group.this
  to   = module.security_group.aws_security_group.this_cbd[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.listener
  to   = module.security_group.aws_vpc_security_group_ingress_rule.this
}

moved {
  from = aws_vpc_security_group_egress_rule.vpc
  to   = module.security_group.aws_vpc_security_group_egress_rule.this["vpc"]
}
```

### Behavioural notes for whoever performs this migration

- **`create_before_destroy` — resolved in 1.1.0, use `create_before_destroy_group = true`.**
  ALB's own `aws_security_group.this` sets
  `lifecycle { create_before_destroy = true }` today, so that a change
  forcing replacement (most notably, changing `description`, which is
  immutable on `aws_security_group`) creates the new group and re-attaches it
  before destroying the old one, avoiding a window where the ALB has no
  security group at all. 1.0.0 of this module had no equivalent (preserved
  byte-for-byte from `aws.modules.ecs-service`'s submodule, which never
  needed this guard), which would have been a real regression, not a
  cosmetic difference, if ALB had migrated onto 1.0.0 as-is. 1.1.0 adds
  `create_before_destroy_group` (see `docs/DESIGN.md`, "What changed in
  1.1.0") for exactly this case: the rewrite above already sets it to
  `true`, which reproduces ALB's current guarantee exactly, at the cost of
  one additional `moved`-adjacent fact — the resource this rule set attaches
  to is `aws_security_group.this_cbd[0]`, not `aws_security_group.this[0]`,
  because `create_before_destroy` cannot live on the same resource
  conditionally (Terraform requires it to be a literal). The `moved` blocks
  below already target `this_cbd[0]` accordingly.
- **The group's `name` attribute is generated on the `this_cbd` path (1.2.0).**
  In 1.1.0 `this_cbd` used the fixed `name = var.name`, so a description-only
  change failed with `InvalidGroup.Duplicate` (the replacement was created
  first, with the same name, in the same VPC). From 1.2.0 `this_cbd` uses
  `name_prefix = "${var.name}-"`: with this rewrite the group's name becomes
  `<var.name>-alb-` followed by a 26-character AWS-generated suffix instead of
  exactly `"${var.name}-alb"`, and the `Name` tag stays `"${var.name}-alb"`
  via `local.tags`. Consequently the `moved` block from ALB's fixed-name
  inline group to `this_cbd[0]` is **not** a zero-change move: the first plan
  shows one create-before-destroy replacement of the group (`name_prefix`
  forces it), its rules re-created on the new group, and a new group ID
  flowing into the load balancer's `security_groups`. The same one-time
  replacement applies to a caller already on 1.1.0 with
  `create_before_destroy_group = true`. Anything outside this module that
  references the old group ID (another group's rule, for example) blocks the
  old group's deletion until it is updated too.
- **The `CKV_AWS_260` skip relocation** above is the other consequence of
  moving a resource across a module boundary: inline `checkov:skip` comments
  do not travel with `moved` blocks, only the state does. Confirm the
  ALB repository's Checkov configuration actually silences `CKV_AWS_260` for
  the new `module.security_group` call after migrating, or the pipeline
  regresses to red on a finding that was previously suppressed for a reason
  that still applies (`ADR-0004`, a deliberately public ALB).
- **Tagging is unchanged in content but the mechanism differs slightly.**
  ALB's inline code tags the group with `local.tags` (`merge({ Name =
  var.name }, var.tags)`) and never overrides it per rule. This module tags
  the group with `merge(var.tags, { Name = var.name })` — passing
  `tags = local.tags` as shown reproduces the same group `Name` tag
  (`var.name`, not `"${var.name}-alb"`) as before, since `local.tags` already
  carries `Name = var.name`. Rule-level tags do change: today's rules carry
  no `Name` tag; this module tags every rule
  `merge(var.tags, { Name = "${var.name}-alb-${key}" })`. This is a strict
  addition (new tags on the rule resources), not a removal, and needs no
  `moved` block, but it does mean an idempotency check that asserts zero tag
  drift on the ingress/egress rules will see a diff, once, on migration.
