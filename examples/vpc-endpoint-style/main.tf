# Reproduces, with this module, the exact security group that
# aws.modules.vpc's modules/endpoints hand-rolls today for interface (
# PrivateLink) endpoints: HTTPS from a list of VPC CIDR blocks, and no
# egress at all (interface endpoints do not need it; AWS terminates the
# connection at the endpoint's own network interface). See docs/CONSUMERS.md
# for the moved-block migration that lets modules/endpoints call this module
# instead of keeping its own aws_security_group.this /
# aws_vpc_security_group_ingress_rule.https resources.
#
# Compare with modules/endpoints/main.tf in aws.modules.vpc (read-only
# reference): the same "one rule per CIDR block, keyed by position" shape,
# reproduced here with this module's ingress_rules map instead of a second,
# independent for_each resource.

provider "aws" {
  region = var.region
}

module "security_group" {
  source = "../../"

  name        = "platform-interface-endpoints"
  description = "Permits private HTTPS connections from this VPC to its AWS interface endpoints."
  vpc_id      = var.vpc_id

  ingress_rules = {
    for index, cidr in var.vpc_cidr_blocks : tostring(index) => {
      description = "HTTPS from the VPC"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = cidr
    }
  }

  # No egress_rules: interface endpoints need none, and this module starts
  # with no implicit egress by design (see the root README's "No implicit
  # egress").

  tags = { Environment = "prod" }
}
