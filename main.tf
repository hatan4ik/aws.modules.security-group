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

resource "aws_security_group" "this" {
  # checkov:skip=CKV2_AWS_5: The group is attached to whatever the caller's network configuration is (an ECS service, a set of interface endpoints, an ALB) outside this module; Checkov's graph cannot follow a module output to that attachment.
  count = var.create ? 1 : 0

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

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for key, rule in var.ingress_rules : key => rule if var.create }

  security_group_id = aws_security_group.this[0].id

  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this[0].id : each.value.referenced_security_group_id

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for key, rule in var.egress_rules : key => rule if var.create }

  security_group_id = aws_security_group.this[0].id

  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this[0].id : each.value.referenced_security_group_id

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}
