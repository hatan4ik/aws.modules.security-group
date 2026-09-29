variable "region" {
  description = "AWS region the security group is created in."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "vpc_cidr_blocks" {
  description = "CIDR blocks allowed to reach the interface endpoints over HTTPS, mirroring aws.modules.vpc's modules/endpoints variable of the same name."
  type        = list(string)
  default     = ["10.0.0.0/16", "10.1.0.0/16"]
}
