output "security_group_id" {
  description = "ID of the created security group."
  value       = module.security_group.id
}

output "ingress_rule_ids" {
  description = "Ingress rule IDs keyed by rule key."
  value       = module.security_group.ingress_rule_ids
}
