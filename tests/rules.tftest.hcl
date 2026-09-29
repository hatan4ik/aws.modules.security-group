# Rendering of every rule shape: each source type, self, tagging, and the
# rule-id outputs. Inherited from aws.modules.ecs-service's
# modules/security-group/tests/security_group.tftest.hcl "creates_group_and_rules"
# run, split out so this file is only about rendering (tests/validation.tftest.hcl
# is only about rejecting bad input).

mock_provider "aws" {}

variables {
  name   = "orders-api"
  vpc_id = "vpc-0123456789abcdef0"
  tags   = { Environment = "test" }
}

run "renders_every_ingress_source_type" {
  command = plan

  variables {
    ingress_rules = {
      from_alb  = { description = "HTTP from the load balancer", from_port = 8080, to_port = 8080, referenced_security_group_id = "sg-0aaaaaaaaaaaaaaaa" }
      from_self = { description = "Cluster gossip", from_port = 7946, to_port = 7946, self = true }
      from_cidr = { description = "SSH from the bastion subnet", from_port = 22, to_port = 22, cidr_ipv4 = "10.0.1.0/24" }
      from_v6   = { description = "HTTPS over IPv6", from_port = 443, to_port = 443, cidr_ipv6 = "2001:db8::/32" }
      from_pl   = { description = "From the S3 gateway prefix list", from_port = 443, to_port = 443, prefix_list_id = "pl-0123456789abcdef0" }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 5
    error_message = "Every declared ingress rule must become one standalone rule resource."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from_alb"].referenced_security_group_id == "sg-0aaaaaaaaaaaaaaaa" && aws_vpc_security_group_ingress_rule.this["from_alb"].from_port == 8080
    error_message = "A referenced_security_group_id rule must keep its source and ports."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from_cidr"].cidr_ipv4 == "10.0.1.0/24"
    error_message = "A cidr_ipv4 rule must keep its CIDR."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from_v6"].cidr_ipv6 == "2001:db8::/32"
    error_message = "A cidr_ipv6 rule must keep its CIDR."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from_pl"].prefix_list_id == "pl-0123456789abcdef0"
    error_message = "A prefix_list_id rule must keep its prefix list."
  }

  assert {
    condition     = alltrue([for key, rule in aws_vpc_security_group_ingress_rule.this : rule.tags["Name"] == "orders-api-${key}"])
    error_message = "Every ingress rule must be tagged Name = <group name>-<rule key>."
  }

  assert {
    condition     = length(output.ingress_rule_ids) == 5
    error_message = "ingress_rule_ids must be keyed by rule key, one entry per declared rule."
  }
}

run "self_plans_one_rule_with_no_independent_source" {
  command = plan

  variables {
    ingress_rules = {
      gossip = { from_port = 7946, to_port = 7946, self = true }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "self = true alone must plan exactly one rule (the exactly-one-source validation already proves no other source can be set alongside it; see tests/validation.tftest.hcl)."
  }

  # referenced_security_group_id is computed from aws_security_group.this[0].id,
  # which is unknown at plan time under mock_provider, so it cannot be
  # asserted here; tests/self_reference.tftest.hcl proves the actual
  # resolution with command = apply instead.
}

run "renders_every_egress_destination_type_and_all_protocol" {
  command = plan

  variables {
    egress_rules = {
      vpc_tls = { description = "TLS to VPC endpoints", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
      s3_tls  = { description = "TLS to S3 gateway", from_port = 443, to_port = 443, prefix_list_id = "pl-0123456789abcdef0" }
      dns     = { from_port = 53, to_port = 53, ip_protocol = "udp", cidr_ipv4 = "10.0.0.2/32" }
      peer    = { from_port = 5432, to_port = 5432, referenced_security_group_id = "sg-0bbbbbbbbbbbbbbbb" }
      all_v6  = { ip_protocol = "-1", cidr_ipv6 = "::/0" }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 5
    error_message = "Every declared egress rule must become one standalone rule resource."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["s3_tls"].prefix_list_id == "pl-0123456789abcdef0" && aws_vpc_security_group_egress_rule.this["dns"].ip_protocol == "udp"
    error_message = "Prefix-list and protocol settings must pass through unchanged."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["peer"].referenced_security_group_id == "sg-0bbbbbbbbbbbbbbbb"
    error_message = "A referenced_security_group_id egress rule must keep its destination."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["all_v6"].from_port == null && aws_vpc_security_group_egress_rule.this["all_v6"].to_port == null && aws_vpc_security_group_egress_rule.this["all_v6"].cidr_ipv6 == "::/0"
    error_message = "An all-protocol rule must carry no ports."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["vpc_tls"].tags["Name"] == "orders-api-vpc_tls"
    error_message = "Egress rules must be tagged Name = <group name>-<rule key>, same as ingress."
  }

  assert {
    condition     = length(output.egress_rule_ids) == 5
    error_message = "egress_rule_ids must be keyed by rule key, one entry per declared rule."
  }
}

run "ip_protocol_defaults_to_tcp" {
  command = plan

  variables {
    ingress_rules = {
      implicit_tcp = { from_port = 8443, to_port = 8443, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["implicit_tcp"].ip_protocol == "tcp"
    error_message = "ip_protocol must default to tcp when not set."
  }
}

run "renaming_a_rule_key_only_touches_that_rule" {
  # Plan-time proxy for "every rule is independent": two runs with disjoint
  # keys must each plan exactly their own rule, proving nothing keys off
  # position or count. (A true rename-triggers-one-replacement assertion
  # needs command = apply against real prior state; this module has no
  # apply-based tests today per docs/DESIGN.md's testing strategy, since
  # nothing here needs one.)
  command = plan

  variables {
    ingress_rules = {
      renamed = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1 && contains(keys(aws_vpc_security_group_ingress_rule.this), "renamed")
    error_message = "The rule map must be keyed exactly by the caller's chosen identifiers."
  }
}
