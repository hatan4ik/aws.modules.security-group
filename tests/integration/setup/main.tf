# Disposable prerequisite for tests/integration/smoke.tftest.hcl: a bare VPC,
# named with a random suffix so concurrent runs never collide. The smoke
# suite only needs a real vpc_id and the VPC's own CIDR block (to prove a
# cidr_ipv4 egress rule scoped to it); it needs no subnets, gateway, or route
# table, since this module attaches nothing to a subnet. Everything here is
# created and destroyed entirely by `terraform test` in the caller's own
# account; nothing is shared or long-lived.

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name = "${var.name_prefix}-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    Name            = local.name
    IntegrationTest = "aws.modules.security-group"
    Disposable      = "true"
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = local.tags
}
