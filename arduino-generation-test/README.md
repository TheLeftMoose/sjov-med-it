# Arduino generation test

This experiment compares how different model and harness combinations respond
to a progressively constrained Arduino code-generation task.

The task begins as a simple request to blink an LED on pin 13. Each subsequent
message removes an implementation option or introduces a new hint. The test is
intended to evaluate context retention, constraint handling, code reasoning,
and whether the model recognizes when the complete set of requirements cannot
guarantee the requested timing.

## Model and harness

The model and the harness are recorded separately:

- **Model:** The language model that generates the response, such as a Claude,
  GPT, or Gemini model.
- **Harness:** The product, client, agent, or integration through which the
  model is used, such as GitHub Copilot CLI, Claude Code, a GitHub coding
  agent, a custom agent, or a direct API script.

The same model can behave differently across harnesses because the harness may
add system instructions, repository context, tools, skills, agents, or an
execution loop. A benchmark run therefore represents a specific combination
of model, harness, configuration, and prompts.

## Running the experiment

1. Start a clean session in the selected harness.
2. Record the harness, model, configuration, and date in a copy of
   [`results/_template.md`](results/_template.md).
3. Send the seven prompts from [`task.md`](task.md) in order.
4. Do not reset the conversation or provide additional hints.
5. Copy each response into the result file without correcting or reformatting
   it.
6. Evaluate the responses using a copy of
   [`reviews/_template.md`](reviews/_template.md).

Use matching filenames for a result and its review:

```text
results/harness--model--run-01.md
reviews/harness--model--run-01.md
```

Examples:

```text
results/copilot-cli--gpt-5-6-sol--run-01.md
results/claude-code--claude-sonnet-5--run-01.md
results/github-custom-agent--model-unknown--run-01.md
```

## Fairness rules

- Use a clean harness session for each run.
- Use the prompts exactly as written.
- Keep model output unchanged, including mistakes.
- Record unavailable harness or model details as `Unknown`.
- Do not expose the expected reasoning or review criteria to the model.
- Record tools, skills, agents, repository context, and internet access made
  available by the harness.
- Note interruptions, retries, automatic actions, or other deviations in the
  run notes.
- Do not commit credentials, private system instructions, unrelated repository
  content, or personal data. Describe inaccessible instructions as `Default`
  or `Not available` rather than attempting to extract them.

## GitHub Copilot CLI harness

The PowerShell harness in `scripts/run-copilot-cli.ps1` runs all seven prompts
through one resumable Copilot CLI session and creates a result file.

Run it from the repository root:

```powershell
.\arduino-generation-test\scripts\run-copilot-cli.ps1 `
  -Model "gpt-5.6-sol" `
  -ReasoningEffort "high"
```

Use `-RunNumber` when repeating the same model and configuration:

```powershell
.\arduino-generation-test\scripts\run-copilot-cli.ps1 `
  -Model "gpt-5.6-sol" `
  -ReasoningEffort "high" `
  -RunNumber 2
```

The harness deliberately:

- Reads the prompts directly from `task.md`.
- Uses the same Copilot session for every turn.
- Runs from an empty working directory outside the repository.
- Uses an isolated per-run home and Copilot configuration directory.
- Disables repository custom instructions and built-in MCP servers.
- Prevents personal skills, plugins, MCP servers, hooks, memory, and IDE
  auto-connect settings from being inherited.
- Exposes no tools to the model.
- Disables remote session export.
- Stops rather than overwriting an existing result unless `-Force` is used.

These settings make this harness a text-only baseline. Runs made with tools,
repository instructions, custom agents, or other Copilot features should use a
different harness name and record those features in the result metadata.

Organization-enforced Copilot policies and the Copilot CLI's own system prompt
remain part of the harness and cannot be removed by this script.

## Clean CLI environment

The repository-level dev container includes both GitHub Copilot CLI and Claude
Code without inheriting their host-level configuration. Rebuild the container
before a clean benchmark series, authenticate each CLI inside the container,
and run the prompts in a fresh session.

The dev container itself is part of the harness. Record it using a distinct
harness name, for example:

```text
copilot-cli-devcontainer--gpt-5-6-sol--run-01.md
claude-code-devcontainer--claude-sonnet--run-01.md
```

Built-in system instructions, built-in capabilities, and organization-enforced
policies remain part of each CLI harness and must be recorded rather than
treated as removable user configuration.

## Automated test process

Rebuild the dev container before a clean benchmark series. Authenticate the
selected CLI inside the container, then run:

```bash
./arduino-generation-test/scripts/run-benchmark.sh \
  copilot-cli \
  gpt-5.6-sol \
  high \
  1
```

For Claude Code:

```bash
./arduino-generation-test/scripts/run-benchmark.sh \
  claude-code \
  sonnet \
  high \
  1
```

Use `--dry-run` to validate the harness, version, prompts, model selection, and
result name without making model calls:

```bash
./arduino-generation-test/scripts/run-benchmark.sh \
  copilot-cli \
  gpt-5.6-sol \
  high \
  1 \
  --dry-run
```

The script reads all prompts from `task.md`, runs them in order in one session,
and creates the correctly named result file. If a turn fails, it preserves the
responses collected so far in a `.partial.md` file.

Each turn records:

- Wall-clock duration measured by the runner.
- CLI-reported duration when available.
- Input, output, cache-read, and cache-write tokens when reported.
- Reported cost when available.

The runner does not estimate missing usage. Unsupported or absent values are
recorded as `Unknown`. Wall-clock duration includes local CLI and network
overhead, while CLI-reported duration and token accounting follow the selected
harness's own definitions.

For every model process, the runner removes forwarded host tokens, Git
credential helpers, and SSH agent sockets. It also disables custom
instructions, tools, MCP servers, plugins, skills, IDE integration, memory,
remote features, and model fallback where the selected CLI provides a control.

Authentication is intentionally not automated. Sign in from inside the
disposable container so credentials are not forwarded from the host or stored
in the repository.

After a successful run:

1. Copy `reviews/_template.md` to the matching filename in `reviews/`.
2. Score the eight criteria using evidence from the generated result.
3. Commit the result and review together.
4. Rebuild the container before the next fully isolated benchmark series.
