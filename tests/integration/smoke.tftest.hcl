# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow). The setup module creates a disposable, subnet-less VPC
# (tests/integration/setup), the security-group module is applied for real
# with one ingress rule (SSH from a private CIDR) and one egress rule (HTTPS
# scoped to the disposable VPC's own CIDR), the results are asserted against
# the real API, and everything is destroyed at the end of the file.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "sg-it"
  }
}

run "smoke" {
  variables {
    name        = run.setup.name
    description = "Integration test group for aws.modules.security-group"
    vpc_id      = run.setup.vpc_id

    ingress_rules = {
      ssh = {
        description = "SSH from a private management CIDR"
        from_port   = 22
        to_port     = 22
        cidr_ipv4   = "10.255.255.0/24"
      }
    }

    egress_rules = {
      https = {
        description = "HTTPS within the disposable VPC only"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = run.setup.vpc_cidr
      }
    }

    tags = run.setup.tags
  }

  assert {
    condition     = aws_security_group.this[0].name == run.setup.name && aws_security_group.this[0].vpc_id == run.setup.vpc_id
    error_message = "The real security group must use the declared name and belong to the disposable VPC."
  }

  assert {
    condition     = startswith(output.id, "sg-") && output.id == aws_security_group.this[0].id
    error_message = "The real API must return a genuine security group ID, and the id output must match it."
  }

  assert {
    condition     = startswith(output.arn, "arn:") && strcontains(output.arn, ":security-group/")
    error_message = "The arn output must be a genuine security group ARN."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1 && length(aws_vpc_security_group_egress_rule.this) == 1
    error_message = "Exactly the one declared ingress rule and one declared egress rule must exist against the real API."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["ssh"].cidr_ipv4 == "10.255.255.0/24" && aws_vpc_security_group_ingress_rule.this["ssh"].from_port == 22 && aws_vpc_security_group_ingress_rule.this["ssh"].to_port == 22
    error_message = "The real ingress rule must carry the requested CIDR and ports."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["https"].cidr_ipv4 == run.setup.vpc_cidr
    error_message = "The real egress rule must be scoped to the disposable VPC's own CIDR, not left unrestricted."
  }

  assert {
    condition     = length(output.ingress_rule_ids) == 1 && length(output.egress_rule_ids) == 1 && startswith(output.ingress_rule_ids["ssh"], "sgr-") && startswith(output.egress_rule_ids["https"], "sgr-")
    error_message = "Rule id outputs must expose genuine AWS rule identifiers (sgr-...) keyed by rule."
  }

  assert {
    condition     = aws_security_group.this[0].tags["IntegrationTest"] == "aws.modules.security-group" && aws_security_group.this[0].tags["Name"] == run.setup.name
    error_message = "The real group must carry the caller's tags merged with the module's own Name tag."
  }
}
