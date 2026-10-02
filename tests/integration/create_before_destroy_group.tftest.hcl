# Integration suite: real apply in the caller's own account.
#
# Proves the scenario create_before_destroy_group exists for, against the real
# API, which tests/ (mock_provider) cannot: with the flag on, a
# description-only change forces AWS to replace the group, and the
# replacement is created while the old group still exists in the same VPC.
# Before 1.2.0 this failed with InvalidGroup.Duplicate because both
# generations used the fixed name = var.name; since 1.2.0 each generation is
# named from name_prefix = "<name>-" plus an AWS-generated unique suffix.
#
# The second run applies to the same state as the first, so a passing
# description_only_change run means: Terraform planned a create-before-destroy
# replacement, AWS accepted the new group alongside the old one, the rule was
# re-created on the new group, and the old group was then deleted (a failed
# delete fails the apply). Everything is destroyed at the end of the file.
#
# Requires AWS credentials and a region from the environment, exactly like
# smoke.tftest.hcl; see README.md.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/create_before_destroy_group.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "sg-it-cbd"
  }
}

run "first_generation" {
  variables {
    name                        = run.setup.name
    description                 = "Integration test group for aws.modules.security-group (generation 1)"
    vpc_id                      = run.setup.vpc_id
    create_before_destroy_group = true

    ingress_rules = {
      https = {
        description = "HTTPS from a private CIDR"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "10.255.255.0/24"
      }
    }

    tags = run.setup.tags
  }

  assert {
    condition     = length(aws_security_group.this) == 0 && length(aws_security_group.this_cbd) == 1
    error_message = "create_before_destroy_group = true must manage the group through aws_security_group.this_cbd."
  }

  assert {
    condition     = startswith(aws_security_group.this_cbd[0].name, "${run.setup.name}-") && aws_security_group.this_cbd[0].name != run.setup.name
    error_message = "The real group name must be AWS-generated from name_prefix = \"<name>-\", not the fixed name."
  }

  assert {
    condition     = startswith(output.id, "sg-") && aws_security_group.this_cbd[0].tags["Name"] == run.setup.name
    error_message = "The group must be real and keep Name = var.name as its tag."
  }
}

run "description_only_change" {
  variables {
    name                        = run.setup.name
    description                 = "Integration test group for aws.modules.security-group (generation 2)"
    vpc_id                      = run.setup.vpc_id
    create_before_destroy_group = true

    ingress_rules = {
      https = {
        description = "HTTPS from a private CIDR"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "10.255.255.0/24"
      }
    }

    tags = run.setup.tags
  }

  assert {
    condition     = output.id != run.first_generation.id && startswith(output.id, "sg-")
    error_message = "A description-only change must replace the group (new id); the apply succeeding at all proves the replacement did not collide with the old group's name."
  }

  assert {
    condition     = aws_security_group.this_cbd[0].description == "Integration test group for aws.modules.security-group (generation 2)" && startswith(aws_security_group.this_cbd[0].name, "${run.setup.name}-")
    error_message = "The replacement must carry the new description and a name generated from the same prefix."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["https"].security_group_id == output.id && startswith(output.ingress_rule_ids["https"], "sgr-")
    error_message = "The rule must be re-created on the replacement group."
  }
}
