# Self-referencing cluster

`self = true` for a clustered service's own gossip traffic, the pattern called out in the root README's "self for same-group traffic" and inherited from `aws.modules.ecs-service`'s original submodule README. A clustered cache (Redis, Memcached, or similar) needs three things from its security group:

- Application traffic from a known peer — here, the load balancer's own security group, via `referenced_security_group_id`.
- Gossip between the cluster's own members, over both TCP and UDP, where the source is "this same group" rather than any fixed CIDR or peer group. `self = true` sets `referenced_security_group_id` to the group's own ID once it exists, so every member of the group can reach every other member on the gossip port without naming the group's own (not-yet-known) ID by hand.
- Egress scoped to the VPC, not the open internet.

## Run

```sh
terraform init
terraform plan
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_security_group"></a> [security\_group](#module\_security\_group) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_security_group_id"></a> [alb\_security\_group\_id](#input\_alb\_security\_group\_id) | Security group of the load balancer that forwards to this cluster. | `string` | `"sg-0aaaaaaaaaaaaaaaa"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the security group is created in. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the security group belongs to. | `string` | `"vpc-0123456789abcdef0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ingress_rule_ids"></a> [ingress\_rule\_ids](#output\_ingress\_rule\_ids) | Ingress rule IDs keyed by rule key. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the created security group. |
<!-- END_TF_DOCS -->
