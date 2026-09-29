variable "region" {
  description = "AWS region the security group is created in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name of the load balancer this security group fronts, mirroring aws.modules.alb's var.name."
  type        = string
  default     = "public-web"
}

variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "security_group_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the load balancer's listeners, mirroring aws.modules.alb's variable of the same name."
  type        = set(string)
  default     = ["0.0.0.0/0"]
}

variable "active_listener_ports" {
  description = "Listener ports to open ingress for, mirroring aws.modules.alb's locals.active_listener_ports (443 when an HTTPS listener exists, 80 when an HTTP listener -- redirect or HTTP-only -- exists)."
  type        = set(string)
  default     = ["443", "80"]
}
