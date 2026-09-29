# Reproduces, with this module, the exact security group that aws.modules.alb
# hand-rolls today in security_group.tf: one ingress rule per (active
# listener port, CIDR) pair, and one egress rule scoped to the VPC's own
# CIDR block instead of the open internet. See docs/CONSUMERS.md for the
# moved-block migration that lets aws.modules.alb call this module instead
# of keeping its own aws_security_group.this /
# aws_vpc_security_group_ingress_rule.listener /
# aws_vpc_security_group_egress_rule.vpc resources.
#
# The VPC CIDR lookup stays at the call site, exactly as it does in
# aws.modules.alb today: this module performs no data-source reads by
# design (docs/DESIGN.md, "Dependency inversion"), so a caller who needs a
# value it does not already have -- here, the VPC's own CIDR block, for the
# egress rule -- looks it up itself.

provider "aws" {
  region = var.region
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

locals {
  # Same shape as aws.modules.alb's locals.ingress_rules: one entry per
  # (port, CIDR) pair, keyed so that the key is stable and human-readable.
  ingress_rules = {
    for pair in setproduct(var.active_listener_ports, var.security_group_ingress_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = tonumber(pair[0]), cidr = pair[1] }
  }
}

module "security_group" {
  source = "../../"

  name        = "${var.name}-alb"
  description = "Controls access to the ${var.name} ALB's listeners; egress is scoped to the VPC CIDR only."
  vpc_id      = var.vpc_id

  ingress_rules = {
    for key, rule in local.ingress_rules : key => {
      description = "Allow inbound ${rule.port} from ${rule.cidr}."
      from_port   = rule.port
      to_port     = rule.port
      ip_protocol = "tcp"
      cidr_ipv4   = rule.cidr
    }
  }

  egress_rules = {
    vpc = {
      description = "Allow all outbound traffic within the VPC only; no unrestricted egress."
      ip_protocol = "-1"
      cidr_ipv4   = data.aws_vpc.this.cidr_block
    }
  }

  tags = { Name = var.name, Environment = "prod" }
}
