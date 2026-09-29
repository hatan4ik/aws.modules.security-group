# Integration fixture

A disposable prerequisite for `tests/integration/smoke.tftest.hcl`: a bare VPC, named with a random suffix so concurrent runs never collide. This module needs no subnets, internet gateway, or route table to prove itself against the real API -- it attaches nothing to a subnet -- so the fixture is smaller than the VPC-with-subnets fixtures `aws.modules.alb` and `aws.modules.ecs` need. Not a deployable pattern: excluded from policy scanning (`.checkov.yml`, `trivy.yaml`) and created and destroyed entirely by `terraform test`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6.0, < 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | CIDR block of the disposable VPC. | `string` | `"10.92.0.0/16"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for every disposable resource name; a random suffix is appended. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged onto every disposable resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_name"></a> [name](#output\_name) | Disposable resource name prefix, including the random suffix. |
| <a name="output_tags"></a> [tags](#output\_tags) | Tags applied to every disposable resource, for reuse on the module under test. |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | CIDR block of the disposable VPC. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | Disposable VPC ID. |
<!-- END_TF_DOCS -->
