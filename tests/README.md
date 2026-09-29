# Contract tests

Mock-provider tests (`mock_provider "aws" {}`, `command = plan`, no credentials, no real resources) that pin this module's interface. Run with `make test` or `terraform test`.

| File | Covers |
| --- | --- |
| `defaults.tftest.hcl` | Secure defaults with no rules declared, the inherited `description` default, tagging, `create = false` as a real no-op (including when `ingress_rules`/`egress_rules` are non-empty), the `vpc_id` precondition, and the `name` length/prefix validations. |
| `rules.tftest.hcl` | Rendering of every rule source type (`cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, `self`) for both ingress and egress, the `ip_protocol` default, per-rule tagging, and the rule-id outputs. |
| `validation.tftest.hcl` | Every validation branch on `ingress_rules` and `egress_rules`, exercised once for each variable rather than assumed symmetric: the exactly-one-source rule (zero sources, two sources, `self` plus another source), the port-range rule (missing one or both ports, `from_port > to_port`, out of `-1..65535`), and the all-protocol (`ip_protocol = "-1"`) rule rejecting any port. |
| `self_reference.tftest.hcl` | The one case needing `command = apply`: `self = true`'s `referenced_security_group_id` resolves to the group's own real `id` (computed attributes are unknown under `mock_provider` at plan time, so this cannot be asserted with `command = plan`). Isolated into its own file, since an `apply` run's state would otherwise leak into every later `plan` run in the same file. |

Every other file uses `command = plan` only.

## What is deliberately not tested here

The immutable-`description`-replaces-the-group behaviour (see the README's "Description replaces the group" and `docs/DESIGN.md`'s testing-strategy section) is real against the AWS API but was found, empirically, not to be reproducible under `mock_provider`: a changed `description` plans as an in-place update rather than a replacement, because `ForceNew` lives in the provider's internal diff logic, not in the schema `mock_provider` reads. Asserting replacement here would assert something false, so nothing does. See `docs/DESIGN.md` for the full finding.

## Integration suite

`tests/integration/` is a separate, credential-driven suite that applies the module for real. It never runs as part of `terraform test`'s default file discovery (that only picks up `tests/*.tftest.hcl`, not the nested `tests/integration/` directory, and `terraform test -test-directory=tests/integration` is only ever invoked explicitly by `make integration-smoke` or the `integration` workflow). See [integration/README.md](integration/README.md).
