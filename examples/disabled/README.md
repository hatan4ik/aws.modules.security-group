# Disabled security group

`create = false`: the module produces no resources and null `id` / `arn` outputs, regardless of what `ingress_rules` or `egress_rules` contain. This is the shape a caller uses when its own flag decides whether it manages a security group at all — exactly how `aws.modules.vpc`'s `modules/endpoints` threads its `create_security_group` variable through to a security group resource today, and how it would thread it through to this module's `create` input after the migration in `docs/CONSUMERS.md`.

`vpc_id` is not required in this example either: the module's `vpc_id is required when create is true` precondition is a `lifecycle.precondition` on `aws_security_group.this`, which only evaluates for an instance that actually exists, so it never fires when `count` is `0`.

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
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Whether the caller's own flag says to create a security group at all. Mirrors the pattern aws.modules.vpc's modules/endpoints uses with its create\_security\_group variable: the caller's own boolean is threaded straight into this module's create input. | `bool` | `false` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the provider is configured for (no resources are created either way in this example). | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_security_group_arn"></a> [security\_group\_arn](#output\_security\_group\_arn) | Always null in this example: create\_security\_group defaults to false. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Always null in this example: create\_security\_group defaults to false. |
<!-- END_TF_DOCS -->
