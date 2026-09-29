# Isolated from tests/create_before_destroy_group.tftest.hcl because this is
# the one case in that suite needing command = apply (self = true's resolved
# referenced_security_group_id is only known once the group itself is
# created), and an apply run's state would otherwise leak into every later
# plan run in the same file — the same rule that separates
# tests/self_reference.tftest.hcl from the rest of the base suite.

mock_provider "aws" {}

variables {
  name                        = "cache-cluster"
  vpc_id                      = "vpc-0123456789abcdef0"
  create_before_destroy_group = true
  ingress_rules = {
    gossip   = { description = "Cluster gossip between members", from_port = 7946, to_port = 7946, self = true }
    from_alb = { description = "HTTP from the load balancer", from_port = 8080, to_port = 8080, cidr_ipv4 = "10.0.0.0/16" }
  }
  egress_rules = {
    vpc_tls = { description = "TLS to VPC endpoints", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
  }
}

run "self_reference_resolves_against_the_create_before_destroy_resource" {
  command = apply

  assert {
    condition     = length(aws_security_group.this) == 0 && length(aws_security_group.this_cbd) == 1
    error_message = "create_before_destroy_group = true must create aws_security_group.this_cbd, not aws_security_group.this."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["gossip"].referenced_security_group_id == aws_security_group.this_cbd[0].id
    error_message = "self = true must resolve to aws_security_group.this_cbd's own id when create_before_destroy_group is true."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["from_alb"].security_group_id == aws_security_group.this_cbd[0].id && aws_vpc_security_group_egress_rule.this["vpc_tls"].security_group_id == aws_security_group.this_cbd[0].id
    error_message = "Ordinary (non-self) ingress and egress rules must also attach to aws_security_group.this_cbd when create_before_destroy_group is true, not just the self-referencing rule."
  }

  assert {
    condition     = output.id == aws_security_group.this_cbd[0].id && output.arn == aws_security_group.this_cbd[0].arn
    error_message = "The id and arn outputs must equal the create-before-destroy group's real id and arn."
  }
}
