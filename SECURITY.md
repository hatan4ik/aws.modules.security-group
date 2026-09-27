# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan, and the impact you see. Redact account IDs and security group IDs that are not already public.

## What counts

- A module default that weakens security: an implicit egress rule that should not exist (the AWS provider already revokes the default allow-all egress on creation; a regression here would silently reopen it), a rule accepted with more than one source/destination, or a port range accepted outside `-1..65535`.
- A validation bypass: an input the module claims to reject at plan time (the exactly-one-source rule, the port-range rule) that instead reaches the provider.
- A rendering bug that attaches a rule to the wrong security group, or that lets `self = true` resolve to any group other than the one the rule belongs to.
- A tagging bug that silently drops or overwrites a caller-supplied tag.
- A dependency problem in the release pipeline that could publish unverified code.

Findings in your own inputs (for example a rule you chose to open to `0.0.0.0/0`) or in AWS services themselves are out of scope here; report the latter to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

The module is secure by default: no implicit egress (the AWS provider revokes the default allow-all rule on creation, and the module adds nothing unless `egress_rules` declares it), exactly one source or destination validated on every rule before any API call, a port-range rule that rejects ports outside `-1..65535` or `from_port > to_port`, no data sources, and no IAM resources. Every claim is enforced by a validation or a precondition with a `terraform test` case behind it. The reasoning is in [docs/DESIGN.md](docs/DESIGN.md).
