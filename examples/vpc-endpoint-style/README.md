# VPC-endpoint-style security group

Reproduces, with this module, the exact shape `aws.modules.vpc`'s `modules/endpoints` submodule hand-rolls today for interface (PrivateLink) endpoints: one ingress rule per VPC CIDR block, all admitting HTTPS (443/tcp) and nothing else, keyed by the CIDR's position in the list (so an IPAM-allocated CIDR that is unknown until apply still yields a known instance key), and **no egress rules at all** — interface endpoints terminate the connection at their own network interface and never need to originate outbound traffic themselves.

This example exists specifically to prove that `aws.modules.security-group` can replace `modules/endpoints`' inline `aws_security_group.this` / `aws_vpc_security_group_ingress_rule.https` resources without changing the security posture: same rule shape, same "HTTPS from the VPC" description, same per-CIDR keying. `docs/CONSUMERS.md` in this repository works out the exact `moved` block HCL that migration needs, since (unlike `aws.modules.ecs-service`, which already calls an identical submodule and needs no `moved` blocks at all) the endpoints submodule's resource labels differ from this module's and the migration crosses a module boundary.

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
| <a name="input_region"></a> [region](#input\_region) | AWS region the security group is created in. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_cidr_blocks"></a> [vpc\_cidr\_blocks](#input\_vpc\_cidr\_blocks) | CIDR blocks allowed to reach the interface endpoints over HTTPS, mirroring aws.modules.vpc's modules/endpoints variable of the same name. | `list(string)` | <pre>[<br/>  "10.0.0.0/16",<br/>  "10.1.0.0/16"<br/>]</pre> | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the security group belongs to. | `string` | `"vpc-0123456789abcdef0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ingress_rule_ids"></a> [ingress\_rule\_ids](#output\_ingress\_rule\_ids) | One HTTPS rule ID per CIDR block, keyed by its position in vpc\_cidr\_blocks. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the created security group, for attaching to interface endpoints. |
<!-- END_TF_DOCS -->
