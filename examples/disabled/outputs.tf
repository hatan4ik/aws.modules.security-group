output "security_group_id" {
  description = "Always null in this example: create_security_group defaults to false."
  value       = module.security_group.id
}

output "security_group_arn" {
  description = "Always null in this example: create_security_group defaults to false."
  value       = module.security_group.arn
}
