provider "aws" {
  region = var.region
}

# create = false is a real no-op: no security group, no rules, id and arn
# are null. vpc_id is not required in this mode either -- the module's own
# precondition on aws_security_group.this only evaluates for the instance
# that create = true would produce, so it never fires here.
module "security_group" {
  source = "../../"

  create = var.create_security_group
  name   = "unused-when-disabled"

  ingress_rules = {
    # Ignored entirely while create = false, exactly like the rest of the
    # module's inputs beyond create and name; kept here to demonstrate that
    # a non-empty rule map is not an error in this mode.
    would_be_ignored = { from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/8" }
  }
}
