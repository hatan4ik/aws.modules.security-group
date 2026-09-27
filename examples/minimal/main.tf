provider "aws" {
  region = var.region
}

module "security_group" {
  source = "../../"

  name        = "orders-api"
  description = "Tasks of ECS service orders-api"
  vpc_id      = var.vpc_id

  ingress_rules = {
    from_alb = {
      description = "HTTP from the load balancer"
      from_port   = 8080
      to_port     = 8080
      cidr_ipv4   = "10.0.0.0/16"
    }
  }

  egress_rules = {
    https = {
      description = "HTTPS to the rest of the VPC (a NAT gateway, a proxy, or a VPC endpoint)"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "10.0.0.0/16"
    }
  }

  tags = { Environment = "prod" }
}
