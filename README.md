# Sjov med IT

This repository contains small experiments created and evaluated by the group.
Each experiment is kept in its own folder with its task, raw results, and
reviews.

## Experiments

| Experiment | Description | Status |
| --- | --- | --- |
| [Arduino generation test](arduino-generation-test/) | Compares how models handle progressively constrained Arduino code generation. | Ready for results |

## General principles

- Keep model output unchanged in the result files.
- Document the model, harness, and capability profile used for every run.
- Separate raw results from human reviews.
- Keep each experiment self-contained.
- Remove credentials, private repository content, and unrelated personal data
  before committing results.

## Development container

The repository includes a clean dev container with:

- GitHub Copilot CLI `1.0.83`
- Claude Code `2.1.263`

Open the repository with **Dev Containers: Reopen in Container** in VS Code.
The CLIs are installed without using the public npm registry.

The container does not mount host Copilot, Claude, MCP, plugin, skill, or
credential directories. Authentication and user configuration created inside
the container are discarded when it is rebuilt.

VS Code can separately share its host Git credential helper with Dev
Containers. Disable **Dev Containers: Copy Git Config** in your local VS Code
settings when using this container as an isolated benchmark harness. The
benchmark runner also removes forwarded tokens, Git askpass variables, and SSH
agent sockets from each model process.

After the container starts, authenticate interactively as needed:

```bash
COPILOT_HOME=$HOME/.benchmark-copilot-auth copilot login
claude
```

The benchmark runner copies only Copilot's authentication state from that
dedicated directory into a fresh temporary `COPILOT_HOME` for every generation
and review session. It does not copy installed plugins, personal skills, MCP
configuration, hooks, settings, extensions, permissions, or session history.

Do not add tokens to `devcontainer.json`, the Dockerfile, or committed
environment files.

The Arduino benchmark includes validated capability profiles for controlled
skill, plugin, and local MCP comparisons. These capabilities are loaded only
for the selected benchmark run and are not installed into persistent CLI
configuration.

Pull requests authored by the repository owner are approved by a narrowly
scoped GitHub Actions workflow. Pull requests from other contributors still
require an independent approval.
