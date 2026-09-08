# Security policy

## Supported versions

This repository contains experiments rather than a versioned software product.
Security fixes are applied to the default branch only.

## Reporting a vulnerability

Report security issues through GitHub's private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Select **Advisories**.
3. Select **Report a vulnerability**.

Do not include credentials, private system instructions, personal data, or
third-party confidential information in a public issue.

For accidental secret exposure, revoke or rotate the affected credential before
reporting the incident.

## Benchmark capability profiles

Files under `arduino-generation-test/capabilities/` are trusted executable
benchmark configuration. Local plugins and MCP servers can influence model
behavior and MCP server scripts execute inside the dev container.

Capability changes must:

- Contain no credentials, tokens, private URLs, or host credential paths.
- Keep referenced files inside the capability directory.
- Pin external skills to a full public GitHub commit and record their license.
- Use local, pinned, dependency-free implementations where possible.
- Declare every MCP tool exposed to the model.
- Pass `scripts/validate-repository.sh` before merge.

## Owner pull-request approval

The `Approve repository owner pull requests` workflow may approve pull requests
only when GitHub reports the author as `TheLeftMoose`. It uses
`pull_request_target` so the trusted workflow definition comes from the default
branch. The workflow must never check out, execute, source, or evaluate content
from the pull-request branch.
