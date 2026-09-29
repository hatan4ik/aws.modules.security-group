variable "region" {
  description = "AWS region the provider is configured for (no resources are created either way in this example)."
  type        = string
  default     = "us-east-1"
}

variable "create_security_group" {
  description = "Whether the caller's own flag says to create a security group at all. Mirrors the pattern aws.modules.vpc's modules/endpoints uses with its create_security_group variable: the caller's own boolean is threaded straight into this module's create input."
  type        = bool
  default     = false
}
