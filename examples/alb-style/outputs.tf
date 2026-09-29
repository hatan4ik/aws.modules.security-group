output "security_group_id" {
  description = "ID of the created security group, for attaching to the load balancer."
  value       = module.security_group.id
}

output "ingress_rule_ids" {
  description = "One rule ID per (listener port, CIDR) pair, keyed \"<port>-<cidr>\"."
  value       = module.security_group.ingress_rule_ids
}

output "egress_rule_ids" {
  description = "The single VPC-scoped egress rule's ID."
  value       = module.security_group.egress_rule_ids
}
