# Every validation branch on ingress_rules and egress_rules, both directions,
# each with a dedicated failing case. The two variables carry identical
# validation logic (docs/DESIGN.md notes this is inherited byte-for-byte from
# aws.modules.ecs-service's modules/security-group), so every rule below is
# exercised once for ingress and once for egress rather than assuming
# symmetry.
#
# Terraform 1.7 does not short-circuit && / ||, so these validations are
# written as nested conditionals; a naive expect_failures test against only
# one branch would not prove the other branch is reachable, hence the
# doubled-up cases here (both-null, one-null, out-of-range-low,
# out-of-range-high, from > to).

mock_provider "aws" {}

variables {
  name   = "orders-api"
  vpc_id = "vpc-0123456789abcdef0"
}

# --- exactly one source: zero sources -----------------------------------

run "rejects_ingress_rule_without_source" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = 443, to_port = 443 }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_rule_without_source" {
  command = plan

  variables {
    egress_rules = {
      bad = { from_port = 443, to_port = 443 }
    }
  }

  expect_failures = [var.egress_rules]
}

# --- exactly one source: two sources -------------------------------------

run "rejects_ingress_rule_with_two_sources" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16", prefix_list_id = "pl-0123456789abcdef0" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_rule_with_two_sources" {
  command = plan

  variables {
    egress_rules = {
      bad = { from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16", prefix_list_id = "pl-0123456789abcdef0" }
    }
  }

  expect_failures = [var.egress_rules]
}

# --- exactly one source: self plus another source counts as two ---------

run "rejects_ingress_rule_with_self_and_cidr" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16", self = true }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_rule_with_self_and_referenced_security_group" {
  command = plan

  variables {
    egress_rules = {
      bad = { from_port = 443, to_port = 443, referenced_security_group_id = "sg-0aaaaaaaaaaaaaaaa", self = true }
    }
  }

  expect_failures = [var.egress_rules]
}

# --- exactly one source: self alone is valid (control case) -------------

run "accepts_self_alone" {
  command = plan

  variables {
    ingress_rules = {
      gossip = { from_port = 7946, to_port = 7946, self = true }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "self = true with no other source must be accepted as the module's one valid form of same-group traffic."
  }
}

# --- port range: a protocol-specific rule missing both ports ------------

run "rejects_ingress_tcp_rule_without_any_ports" {
  command = plan

  variables {
    ingress_rules = {
      bad = { cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_tcp_rule_without_any_ports" {
  command = plan

  variables {
    egress_rules = {
      bad = { cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.egress_rules]
}

# --- port range: a protocol-specific rule missing exactly one port ------

run "rejects_ingress_rule_missing_to_port" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = 443, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_ingress_rule_missing_from_port" {
  command = plan

  variables {
    ingress_rules = {
      bad = { to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_rule_missing_to_port" {
  command = plan

  variables {
    egress_rules = {
      bad = { from_port = 443, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.egress_rules]
}

# --- port range: from_port greater than to_port --------------------------

run "rejects_ingress_rule_with_from_port_greater_than_to_port" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = 443, to_port = 80, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_rule_with_from_port_greater_than_to_port" {
  command = plan

  variables {
    egress_rules = {
      bad = { from_port = 443, to_port = 80, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.egress_rules]
}

# --- port range: out of the -1..65535 bound -------------------------------

run "rejects_ingress_rule_with_from_port_below_negative_one" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = -5, to_port = 80, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_ingress_rule_with_to_port_above_65535" {
  command = plan

  variables {
    ingress_rules = {
      bad = { from_port = 80, to_port = 70000, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_rule_with_to_port_above_65535" {
  command = plan

  variables {
    egress_rules = {
      bad = { from_port = 80, to_port = 70000, cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  expect_failures = [var.egress_rules]
}

# --- port range: all-protocol rule must not set ports ---------------------

run "rejects_ingress_all_protocol_rule_with_both_ports" {
  command = plan

  variables {
    ingress_rules = {
      bad = { ip_protocol = "-1", from_port = 0, to_port = 0, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_egress_all_protocol_rule_with_both_ports" {
  command = plan

  variables {
    egress_rules = {
      bad = { ip_protocol = "-1", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_ingress_all_protocol_rule_with_only_from_port" {
  command = plan

  variables {
    ingress_rules = {
      bad = { ip_protocol = "-1", from_port = 0, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "accepts_all_protocol_rule_with_no_ports" {
  command = plan

  variables {
    egress_rules = {
      all = { ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["all"].from_port == null && aws_vpc_security_group_egress_rule.this["all"].to_port == null
    error_message = "An all-protocol rule with no ports set must be accepted and planned with null ports."
  }
}

# --- name validation (kept alongside rule validation for completeness;
#     the primary coverage lives in tests/defaults.tftest.hcl) -----------

run "rejects_name_longer_than_255_characters" {
  command = plan

  variables {
    name = join("", [for i in range(256) : "a"])
  }

  expect_failures = [var.name]
}
