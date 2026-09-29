# create_before_destroy is a Terraform meta-argument, not a resource
# attribute: it has no representation a `condition` expression can read, so
# these tests cannot assert "this resource has create_before_destroy = true"
# directly, the same class of limitation documented in docs/DESIGN.md for
# ForceNew under mock_provider. What they can and do assert structurally is
# that exactly one of the two mutually exclusive security-group resources
# exists for a given value of create_before_destroy_group, that the rules and
# outputs attach to whichever one is active, and that main.tf's own source
# literally sets create_before_destroy = true on aws_security_group.this_cbd
# (checked once, directly against the file, since that is the actual
# guarantee this feature makes and a test can at least confirm the line has
# not been deleted or miscopied). The self = true case under
# create_before_destroy_group = true needs command = apply and is isolated in
# tests/create_before_destroy_group_self_reference.tftest.hcl instead, per
# the same apply-run-state-leaks-into-later-plan-runs rule that separates
# tests/self_reference.tftest.hcl from the rest of this suite.

mock_provider "aws" {}

variables {
  name   = "orders-api"
  vpc_id = "vpc-0123456789abcdef0"
  tags   = { Environment = "test" }
}

run "defaults_to_the_original_resource_with_no_create_before_destroy" {
  command = plan

  assert {
    condition     = length(aws_security_group.this) == 1 && length(aws_security_group.this_cbd) == 0
    error_message = "create_before_destroy_group must default to false, keeping the original resource active and creating no this_cbd instance."
  }
}

run "opts_into_the_create_before_destroy_resource" {
  command = plan

  variables {
    create_before_destroy_group = true
    ingress_rules = {
      from_alb = { from_port = 8080, to_port = 8080, cidr_ipv4 = "10.0.0.0/16" }
    }
    egress_rules = {
      vpc_tls = { from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  assert {
    condition     = length(aws_security_group.this) == 0 && length(aws_security_group.this_cbd) == 1
    error_message = "create_before_destroy_group = true must create aws_security_group.this_cbd instead of aws_security_group.this, never both."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1 && length(aws_vpc_security_group_egress_rule.this) == 1
    error_message = "Rules must still render when create_before_destroy_group is true. (Their security_group_id cannot be compared against aws_security_group.this_cbd[0].id under command = plan; both trace to the same unknown computed attribute, which apply-mode tests/create_before_destroy_group_self_reference.tftest.hcl proves is wired correctly instead.)"
  }
}

run "disabled_creates_neither_variant" {
  command = plan

  variables {
    create                      = false
    create_before_destroy_group = true
    ingress_rules               = { from_alb = { from_port = 80, to_port = 80, cidr_ipv4 = "10.0.0.0/8" } }
  }

  assert {
    condition     = length(aws_security_group.this) == 0 && length(aws_security_group.this_cbd) == 0 && output.id == null
    error_message = "create = false must create neither variant regardless of create_before_destroy_group, and outputs must be null."
  }
}

run "main_tf_sets_create_before_destroy_literally_true_on_this_cbd" {
  command = plan

  assert {
    condition     = can(regex("(?s)resource \"aws_security_group\" \"this_cbd\" \\{.*?lifecycle \\{\\s*create_before_destroy = true", file("${path.module}/main.tf")))
    error_message = "aws_security_group.this_cbd must set lifecycle.create_before_destroy = true directly in main.tf; this is the one guarantee create_before_destroy_group actually makes and no test assertion on a resource attribute can verify it."
  }
}
