provider "aws" {
  region = var.region
}

# A clustered cache's task security group: application traffic arrives from
# the ALB's own security group, cluster members gossip with each other over
# a dedicated port using self = true (the shape the root README calls out
# under "self for same-group traffic"), and egress is scoped to the VPC.
module "security_group" {
  source = "../../"

  name        = "cache-cluster"
  description = "Tasks of the cache-cluster service"
  vpc_id      = var.vpc_id

  ingress_rules = {
    from_alb = {
      description                  = "Application traffic from the load balancer"
      from_port                    = 6379
      to_port                      = 6379
      referenced_security_group_id = var.alb_security_group_id
    }
    gossip = {
      description = "Cluster gossip between members of this same security group"
      from_port   = 7946
      to_port     = 7946
      self        = true
    }
    gossip_udp = {
      description = "Cluster gossip (UDP) between members of this same security group"
      from_port   = 7946
      to_port     = 7946
      ip_protocol = "udp"
      self        = true
    }
  }

  egress_rules = {
    vpc = {
      description = "All outbound traffic within the VPC only"
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  }

  tags = { Environment = "prod", Service = "cache-cluster" }
}
