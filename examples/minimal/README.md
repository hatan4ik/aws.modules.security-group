# Minimal security group

The smallest working call of `aws.modules.security-group`: one ingress rule from a CIDR block, one egress rule to a CIDR block. Everything else keeps the module's defaults, including the inherited `description` fallback if you omit it (this example sets its own, as every real caller should — see the root README's "Description replaces the group").

Start here to see exactly what the module needs before adding more rules, `self`-referencing traffic, or a peer security group as a source.

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
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the security group belongs to. | `string` | `"vpc-0123456789abcdef0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_egress_rule_ids"></a> [egress\_rule\_ids](#output\_egress\_rule\_ids) | Egress rule IDs keyed by rule key. |
| <a name="output_ingress_rule_ids"></a> [ingress\_rule\_ids](#output\_ingress\_rule\_ids) | Ingress rule IDs keyed by rule key. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the created security group. |
<!-- END_TF_DOCS -->
