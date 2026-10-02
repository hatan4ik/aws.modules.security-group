# The AWS provider revokes the implicit allow-all egress rule when it creates
# a VPC security group, so the group starts with no rules at all. Every rule
# is a standalone resource so callers can add, change, or remove one without
# touching the others.
#
# This module is an extraction of aws.modules.ecs-service's internal
# modules/security-group submodule (see docs/DESIGN.md): the interface below
# — variable names, types, defaults, validations, resource labels, and
# outputs — is preserved byte-for-byte from that source. Do not change it
# without a major version bump; three sibling repos are meant to call this
# module unmodified.
#
# create_before_destroy_group (added in 1.1.0, see docs/DESIGN.md) is the one
# exception: it is additive and defaults to false, so every existing caller's
# plan is unaffected. Terraform's lifecycle block accepts only literal
# booleans, never a variable or expression, so the toggle cannot live on one
# resource; it is two mutually exclusive resources instead, unified below by
# local.security_group_id/arn so every other resource and output reads one
# value regardless of which variant is active. Since 1.2.0 the
# create-before-destroy variant also uses name_prefix instead of a fixed
# name; see the comment on that resource.

resource "aws_security_group" "this" {
  # checkov:skip=CKV2_AWS_5: The group is attached to whatever the caller's network configuration is (an ECS service, a set of interface endpoints, an ALB) outside this module; Checkov's graph cannot follow a module output to that attachment.
  count = var.create && !var.create_before_destroy_group ? 1 : 0

  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = var.vpc_id != null
      error_message = "vpc_id is required when create is true."
    }
  }
}

resource "aws_security_group" "this_cbd" {
  # checkov:skip=CKV2_AWS_5: The group is attached to whatever the caller's network configuration is (an ECS service, a set of interface endpoints, an ALB) outside this module; Checkov's graph cannot follow a module output to that attachment.
  count = var.create && var.create_before_destroy_group ? 1 : 0

  # name_prefix, not name (changed in 1.2.0): security-group names must be
  # unique per VPC, and create_before_destroy creates the replacement while
  # the old group still exists. With a fixed name = var.name, a
  # description-only change (the headline replacement this resource exists
  # for) failed with InvalidGroup.Duplicate. name_prefix makes AWS append a
  # unique suffix to every generation, so the two never collide. The Name tag
  # stays exactly var.name.
  name_prefix = "${var.name}-"
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.vpc_id != null
      error_message = "vpc_id is required when create is true."
    }

    # The AWS provider caps name_prefix at 229 characters (255 minus its
    # 26-character unique suffix), so var.name plus the "-" separator must fit.
    precondition {
      condition     = length(var.name) <= 228
      error_message = "name must be at most 228 characters when create_before_destroy_group is true, because the group name is generated from name_prefix = \"<name>-\" plus a 26-character unique suffix (255 characters total)."
    }
  }
}

locals {
  security_group_id  = var.create ? (var.create_before_destroy_group ? aws_security_group.this_cbd[0].id : aws_security_group.this[0].id) : null
  security_group_arn = var.create ? (var.create_before_destroy_group ? aws_security_group.this_cbd[0].arn : aws_security_group.this[0].arn) : null
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for key, rule in var.ingress_rules : key => rule if var.create }

  security_group_id = local.security_group_id

  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? local.security_group_id : each.value.referenced_security_group_id

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for key, rule in var.egress_rules : key => rule if var.create }

  security_group_id = local.security_group_id

  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? local.security_group_id : each.value.referenced_security_group_id

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}
