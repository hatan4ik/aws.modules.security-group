# ALB-style security group

Reproduces, with this module, the exact shape `aws.modules.alb` hand-rolls today in `security_group.tf`: one ingress rule per (active listener port, CIDR) pair — by default `443` and `80` from `0.0.0.0/0`, a deliberately public load balancer — and one egress rule that scopes all outbound traffic to the VPC's own CIDR block rather than leaving it unrestricted. The VPC CIDR lookup (`data "aws_vpc" "this"`) stays in this example's own `main.tf`, not in the module: `aws.modules.security-group` performs no data-source reads by design, so a caller that needs a value it does not already have supplies it itself, exactly as `aws.modules.alb` already does.

This example exists specifically to prove that `aws.modules.security-group` can replace `aws.modules.alb`'s inline `aws_security_group.this` / `aws_vpc_security_group_ingress_rule.listener` / `aws_vpc_security_group_egress_rule.vpc` resources without changing the security posture: same per-port-per-CIDR rules, same VPC-scoped egress, same public-by-design ingress (ADR-0004 in `aws.modules.alb`). `docs/CONSUMERS.md` in this repository works out the exact `moved` block HCL that migration needs — including the one behavioural regression worth knowing about first: `aws.modules.alb`'s own security group uses `lifecycle { create_before_destroy = true }` today, and this module's group does not (it is inherited byte-for-byte from `aws.modules.ecs-service`, which never needed it), so migrating trades away that protection against a brief outage on a forced replacement.

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

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_security_group"></a> [security\_group](#module\_security\_group) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_active_listener_ports"></a> [active\_listener\_ports](#input\_active\_listener\_ports) | Listener ports to open ingress for, mirroring aws.modules.alb's locals.active\_listener\_ports (443 when an HTTPS listener exists, 80 when an HTTP listener -- redirect or HTTP-only -- exists). | `set(string)` | <pre>[<br/>  "443",<br/>  "80"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the load balancer this security group fronts, mirroring aws.modules.alb's var.name. | `string` | `"public-web"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the security group is created in. | `string` | `"us-east-1"` | no |
| <a name="input_security_group_ingress_cidrs"></a> [security\_group\_ingress\_cidrs](#input\_security\_group\_ingress\_cidrs) | CIDR blocks allowed to reach the load balancer's listeners, mirroring aws.modules.alb's variable of the same name. | `set(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the security group belongs to. | `string` | `"vpc-0123456789abcdef0"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_egress_rule_ids"></a> [egress\_rule\_ids](#output\_egress\_rule\_ids) | The single VPC-scoped egress rule's ID. |
| <a name="output_ingress_rule_ids"></a> [ingress\_rule\_ids](#output\_ingress\_rule\_ids) | One rule ID per (listener port, CIDR) pair, keyed "<port>-<cidr>". |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the created security group, for attaching to the load balancer. |
<!-- END_TF_DOCS -->
