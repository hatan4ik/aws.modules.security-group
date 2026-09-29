output "security_group_id" {
  description = "ID of the created security group, for attaching to interface endpoints."
  value       = module.security_group.id
}

output "ingress_rule_ids" {
  description = "One HTTPS rule ID per CIDR block, keyed by its position in vpc_cidr_blocks."
  value       = module.security_group.ingress_rule_ids
}
