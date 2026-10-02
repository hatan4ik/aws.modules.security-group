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
#
# Since 1.2.0 aws_security_group.this_cbd is named with name_prefix =
# "<name>-" instead of a fixed name, so the replacement a description change
# forces can be created while the old group (same VPC) still exists. The runs
# below pin that naming contract at plan time; the description-only
# replacement itself is exercised under command = apply in
# tests/create_before_destroy_group_description_change.tftest.hcl and against
# the real API in tests/integration/create_before_destroy_group.tftest.hcl.

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

  assert {
    condition     = aws_security_group.this[0].name == "orders-api"
    error_message = "The default path must keep the fixed name = var.name, byte-identical to 1.0.0/1.1.0; name_prefix applies only to the create-before-destroy variant."
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
    condition     = aws_security_group.this_cbd[0].name_prefix == "orders-api-"
    error_message = "The create-before-destroy group must be named from name_prefix = \"<name>-\" so AWS generates a unique name per generation; a fixed name collides with the old group (InvalidGroup.Duplicate) during create_before_destroy."
  }

  assert {
    condition     = aws_security_group.this_cbd[0].tags["Name"] == "orders-api"
    error_message = "The Name tag must stay exactly var.name on the create-before-destroy path; only the group's name attribute is generated."
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

run "main_tf_names_this_cbd_by_prefix_and_this_by_fixed_name" {
  command = plan

  # Plan-time attribute assertions cannot distinguish "name is unset" from
  # "name is unknown", so the source is checked directly, the same way the
  # create_before_destroy literal is above: this_cbd must set name_prefix and
  # no fixed name, and this must keep its fixed name.
  assert {
    condition = (
      can(regex("(?s)resource \"aws_security_group\" \"this_cbd\" \\{[^}]*?\\n  name_prefix = \"\\$\\{var\\.name\\}-\"", file("${path.module}/main.tf"))) &&
      !can(regex("(?s)resource \"aws_security_group\" \"this_cbd\" \\{[^}]*?\\n  name +=", file("${path.module}/main.tf")))
    )
    error_message = "aws_security_group.this_cbd must set name_prefix = \"$${var.name}-\" and must not set a fixed name."
  }

  assert {
    condition     = can(regex("(?s)resource \"aws_security_group\" \"this\" \\{[^}]*?\\n  name        = var\\.name\\n", file("${path.module}/main.tf")))
    error_message = "aws_security_group.this (the default path) must keep name = var.name."
  }
}

run "rejects_name_too_long_for_name_prefix_on_the_create_before_destroy_path" {
  command = plan

  variables {
    create_before_destroy_group = true
    name                        = join("", [for i in range(229) : "a"])
  }

  expect_failures = [aws_security_group.this_cbd]
}

run "accepts_the_longest_name_that_fits_name_prefix" {
  command = plan

  variables {
    create_before_destroy_group = true
    name                        = join("", [for i in range(228) : "a"])
  }

  assert {
    condition     = length(aws_security_group.this_cbd) == 1
    error_message = "A 228-character name plus the \"-\" separator fills the provider's 229-character name_prefix limit exactly and must be accepted."
  }
}

run "default_path_still_accepts_names_longer_than_228" {
  command = plan

  variables {
    name = join("", [for i in range(255) : "a"])
  }

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "The 228-character cap applies only to the create-before-destroy path; the default path keeps the original 255-character limit."
  }
}
