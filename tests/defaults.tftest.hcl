# Secure defaults, tagging, and the create = false no-op path.
# Inherited from aws.modules.ecs-service's modules/security-group/tests, plus
# a dedicated look at defaults in isolation from any rules.

mock_provider "aws" {}

variables {
  name   = "orders-api"
  vpc_id = "vpc-0123456789abcdef0"
  tags   = { Environment = "test" }
}

run "creates_group_with_no_rules_by_default" {
  command = plan

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "create defaults to true: exactly one security group must be planned."
  }

  assert {
    condition     = aws_security_group.this[0].name == "orders-api" && aws_security_group.this[0].vpc_id == "vpc-0123456789abcdef0"
    error_message = "The security group must use the declared name and VPC."
  }

  assert {
    condition     = aws_security_group.this[0].description == "ECS task security group"
    error_message = "description must default to \"ECS task security group\" (inherited byte-for-byte from the source submodule; see docs/DESIGN.md)."
  }

  assert {
    condition     = aws_security_group.this[0].tags["Name"] == "orders-api" && aws_security_group.this[0].tags["Environment"] == "test"
    error_message = "The group must carry a Name tag equal to its name, merged with caller tags."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 0 && length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "With no ingress_rules or egress_rules declared, no rule resources must be planned: no implicit egress or ingress."
  }

  assert {
    condition     = length(output.ingress_rule_ids) == 0 && length(output.egress_rule_ids) == 0
    error_message = "Rule ID outputs must be empty maps when no rules are declared."
  }
}

run "custom_description_is_honoured" {
  command = plan

  variables {
    description = "Custom description"
  }

  assert {
    condition     = aws_security_group.this[0].description == "Custom description"
    error_message = "An explicit description must override the default."
  }
}

run "creates_nothing_when_disabled" {
  command = plan

  variables {
    create        = false
    ingress_rules = { from_alb = { from_port = 80, to_port = 80, cidr_ipv4 = "10.0.0.0/8" } }
    egress_rules  = { all = { ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" } }
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "create = false must plan no security group."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 0 && length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "create = false must plan no rules, even when ingress_rules/egress_rules are non-empty: the rule maps are ignored entirely."
  }

  assert {
    condition     = output.id == null && output.arn == null
    error_message = "create = false must produce null id and arn outputs."
  }

  assert {
    condition     = length(output.ingress_rule_ids) == 0 && length(output.egress_rule_ids) == 0
    error_message = "create = false must produce empty rule id maps, not an error, even though ingress_rules/egress_rules were non-empty."
  }
}

run "requires_vpc_id_when_creating" {
  command = plan

  variables {
    vpc_id = null
  }

  expect_failures = [aws_security_group.this]
}

run "vpc_id_not_required_when_disabled" {
  command = plan

  variables {
    create = false
    vpc_id = null
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "vpc_id must not be required when create is false: the precondition on aws_security_group.this only evaluates for the created instance."
  }
}

run "rejects_name_starting_with_sg_prefix" {
  command = plan

  variables {
    name = "sg-not-allowed"
  }

  expect_failures = [var.name]
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}
