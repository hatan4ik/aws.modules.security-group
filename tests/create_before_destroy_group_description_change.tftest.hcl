# The headline scenario create_before_destroy_group exists for: with the flag
# on, change only description (immutable on aws_security_group, so AWS forces
# a replacement) and the replacement must be creatable while the old group
# still exists in the same VPC. Before 1.2.0 it was not: this_cbd used a fixed
# name = var.name, the replacement reused it, and AWS rejected the create with
# InvalidGroup.Duplicate (group names are unique per VPC).
#
# What mock_provider can and cannot show here. It cannot reproduce the
# replacement itself: ForceNew lives in the provider's own diff logic, not in
# the schema mock_provider reads, so a description change plans as an
# in-place update (see tests/README.md, "What is deliberately not tested
# here"), and it has no notion of per-VPC name uniqueness. What it does show,
# across two applies to the same state that differ only in description, is
# the naming contract that makes the real replacement collision-free: the
# group is named from name_prefix = "<name>-" in both generations, its name
# attribute is never pinned to the caller's fixed name, and the Name tag and
# rule attachments are unaffected. The real replacement (new group id, old
# group destroyed after, no duplicate-name error) is proven against the AWS
# API by tests/integration/create_before_destroy_group.tftest.hcl.
#
# Isolated in its own file because it needs command = apply, whose state
# would otherwise leak into the plan runs of
# tests/create_before_destroy_group.tftest.hcl.

mock_provider "aws" {}

variables {
  name                        = "orders-alb"
  vpc_id                      = "vpc-0123456789abcdef0"
  create_before_destroy_group = true
  ingress_rules = {
    https = { description = "HTTPS from the internal network", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/8" }
  }
}

run "first_generation" {
  command = apply

  variables {
    description = "Controls access to the orders ALB (v1)"
  }

  assert {
    condition     = aws_security_group.this_cbd[0].name_prefix == "orders-alb-" && aws_security_group.this_cbd[0].name != "orders-alb"
    error_message = "The create-before-destroy group must be named from name_prefix = \"orders-alb-\", never the fixed name \"orders-alb\" that the next generation would collide with."
  }

  assert {
    condition     = aws_security_group.this_cbd[0].description == "Controls access to the orders ALB (v1)"
    error_message = "The first generation must carry the first description."
  }
}

run "description_only_change" {
  command = apply

  variables {
    description = "Controls access to the orders ALB (v2)"
  }

  assert {
    condition     = aws_security_group.this_cbd[0].description == "Controls access to the orders ALB (v2)"
    error_message = "The description change must be applied."
  }

  assert {
    condition     = aws_security_group.this_cbd[0].name_prefix == "orders-alb-" && aws_security_group.this_cbd[0].name != "orders-alb"
    error_message = "After a description-only change the group must still be named from name_prefix = \"orders-alb-\" and not pinned to the fixed name, so the replacement AWS forces gets its own unique name instead of colliding with the group it replaces."
  }

  assert {
    condition     = length(aws_security_group.this) == 0 && length(aws_security_group.this_cbd) == 1
    error_message = "A description-only change must stay on the create-before-destroy resource; it must never fall back to aws_security_group.this."
  }

  assert {
    condition     = aws_security_group.this_cbd[0].tags["Name"] == "orders-alb"
    error_message = "The Name tag must stay exactly var.name across generations."
  }

  assert {
    condition     = output.id == aws_security_group.this_cbd[0].id && aws_vpc_security_group_ingress_rule.this["https"].security_group_id == aws_security_group.this_cbd[0].id
    error_message = "The id output and every rule must follow the current create-before-destroy group."
  }
}
