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
