# Contract tests

Mock-provider tests (`mock_provider "aws" {}`, `command = plan`, no credentials, no real resources) that pin this module's interface. Run with `make test` or `terraform test`.

| File | Covers |
| --- | --- |
| `defaults.tftest.hcl` | Secure defaults with no rules declared, the inherited `description` default, tagging, `create = false` as a real no-op (including when `ingress_rules`/`egress_rules` are non-empty), the `vpc_id` precondition, and the `name` length/prefix validations. |
| `rules.tftest.hcl` | Rendering of every rule source type (`cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, `self`) for both ingress and egress, the `ip_protocol` default, per-rule tagging, and the rule-id outputs. |
| `validation.tftest.hcl` | Every validation branch on `ingress_rules` and `egress_rules`, exercised once for each variable rather than assumed symmetric: the exactly-one-source rule (zero sources, two sources, `self` plus another source), the port-range rule (missing one or both ports, `from_port > to_port`, out of `-1..65535`), and the all-protocol (`ip_protocol = "-1"`) rule rejecting any port. |
| `create_before_destroy_group.tftest.hcl` | `create_before_destroy_group`: exactly one of `aws_security_group.this` / `this_cbd` exists, rules and outputs follow the active one, `create = false` creates neither, `this_cbd` literally sets `create_before_destroy = true`, and (1.2.0) `this_cbd` is named from `name_prefix = "<name>-"` while `this` keeps `name = var.name`, with the 228-character name cap that only the create-before-destroy path carries. |
| `create_before_destroy_group_description_change.tftest.hcl` | `command = apply`: two applies to the same state differing only in `description`, with `create_before_destroy_group = true`, keep the group named from `name_prefix` (never pinned to the fixed name the replacement would collide with), keep the `Name` tag, and keep rules attached. `mock_provider` plans the change in place, so the replacement itself is proven by `tests/integration/create_before_destroy_group.tftest.hcl`. |
| `create_before_destroy_group_self_reference.tftest.hcl` | `command = apply`: `self = true` and ordinary rules resolve against `this_cbd`'s real id when `create_before_destroy_group = true`. |
| `self_reference.tftest.hcl` | The one case needing `command = apply`: `self = true`'s `referenced_security_group_id` resolves to the group's own real `id` (computed attributes are unknown under `mock_provider` at plan time, so this cannot be asserted with `command = plan`). Isolated into its own file, since an `apply` run's state would otherwise leak into every later `plan` run in the same file. |

Every other file uses `command = plan` only.

## What is deliberately not tested here

The immutable-`description`-replaces-the-group behaviour (see the README's "Description replaces the group" and `docs/DESIGN.md`'s testing-strategy section) is real against the AWS API but was found, empirically, not to be reproducible under `mock_provider`: a changed `description` plans as an in-place update rather than a replacement, because `ForceNew` lives in the provider's internal diff logic, not in the schema `mock_provider` reads. Asserting replacement here would assert something false, so nothing does. See `docs/DESIGN.md` for the full finding.

## Integration suite

`tests/integration/` is a separate, credential-driven suite that applies the module for real. It never runs as part of `terraform test`'s default file discovery (that only picks up `tests/*.tftest.hcl`, not the nested `tests/integration/` directory, and `terraform test -test-directory=tests/integration` is only ever invoked explicitly by `make integration-smoke`, `make integration-create_before_destroy_group`, or the `integration` workflow). See [integration/README.md](integration/README.md).
