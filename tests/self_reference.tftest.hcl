# self = true's resolved referenced_security_group_id can only be checked
# against the group's actual id once it is known, which needs
# command = apply under mock_provider (computed attributes are unknown at
# plan time; see tests/rules.tftest.hcl). Isolated into its own file per the
# common v1-uplift rules, since an apply run's state would otherwise leak
# into every later plan run in the same file.

mock_provider "aws" {}

variables {
  name   = "cache-cluster"
  vpc_id = "vpc-0123456789abcdef0"
  ingress_rules = {
    gossip = { description = "Cluster gossip between members", from_port = 7946, to_port = 7946, self = true }
  }
  egress_rules = {
    gossip = { description = "Cluster gossip between members", from_port = 7946, to_port = 7946, self = true }
  }
}

run "self_resolves_to_the_groups_own_id" {
  command = apply

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["gossip"].referenced_security_group_id == aws_security_group.this[0].id
    error_message = "self = true must set the ingress rule's referenced_security_group_id to the group's own id."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["gossip"].referenced_security_group_id == aws_security_group.this[0].id
    error_message = "self = true must set the egress rule's referenced_security_group_id to the group's own id."
  }

  assert {
    condition     = aws_security_group.this[0].id == output.id
    error_message = "The id output must equal the created group's real id."
  }
}
