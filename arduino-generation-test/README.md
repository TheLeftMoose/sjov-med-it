# Arduino generation test

This experiment compares how different model and harness combinations respond
to a progressively constrained Arduino code-generation task.

The task begins as a simple request to blink an LED on pin 13. Each subsequent
message removes an implementation option or introduces a new hint. The test is
intended to evaluate context retention, constraint handling, code reasoning,
and whether the model recognizes when the complete set of requirements cannot
guarantee the requested timing.

## Model and harness

The model, harness, and capability profile are recorded separately:

- **Model:** The language model that generates the response, such as a Claude,
  GPT, or Gemini model.
- **Harness:** The product, client, agent, or integration through which the
  model is used, such as GitHub Copilot CLI, Claude Code, a GitHub coding
  agent, a custom agent, or a direct API script.
- **Capability profile:** The exact skills, plugins, MCP servers, tools, and
  network access intentionally exposed for one run.

The same model can behave differently across harnesses because the harness may
add system instructions, repository context, tools, skills, agents, or an
execution loop. A benchmark run therefore represents a specific combination
of model, harness, capability profile, and prompts.

## Capability profiles

Capability profiles live in [`capabilities/profiles/`](capabilities/profiles/)
and are a third benchmark dimension:

```text
model × harness × capability profile
```

The committed profiles are:

| Profile | Capabilities | Harnesses |
| --- | --- | --- |
| `baseline` | No custom capabilities | Copilot CLI and Claude Code |
| `arduino-skill` | Standalone Arduino reasoning skill | Copilot CLI |
| `arduino-plugin` | Local plugin containing Arduino guidance | Copilot CLI |
| `arduino-mcp` | One local read-only Arduino MCP tool | Copilot CLI |
| `combined` | Skill, plugin, and MCP tool | Copilot CLI |

Run a capability variant with:

```bash
./arduino-generation-test/scripts/run-benchmark.sh \
  copilot-cli \
  gpt-5.6-sol \
  high \
  1 \
  --profile arduino-skill
```

For non-baseline profiles, filenames include the profile:

```text
copilot-cli-devcontainer--gpt-5-6-sol--profile-arduino-skill--run-01.md
```

The runner validates the profile before making model calls, computes a SHA-256
over the profile and referenced capability files, and records the resolved
skills, plugins, MCP servers, tools, URLs, and hash in the result.

Capabilities are never installed into persistent CLI configuration. Standalone
skills are wrapped in a temporary local plugin, committed plugins are loaded
with `--plugin-dir`, and MCP servers are supplied with a temporary
`--additional-mcp-config` file. Only profile-declared MCP tools are visible.
The separate review session does not receive the tested capabilities.

Validate one profile without running a model:

```bash
bash ./arduino-generation-test/scripts/validate-profile.sh arduino-mcp
```

Profile paths are confined to `capabilities/`. MCP fixtures must be local,
dependency-free, and contain no credentials. Profiles store no secret values
or host credential paths.

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

## Selecting a model

Model availability depends on the signed-in account, provider, organization
policy, and CLI version. Use the CLI's live model picker instead of maintaining
a fixed list in this repository. The runner validates Copilot model input
against the identifiers exposed by the installed CLI and normalizes equivalent
capitalization, spaces, and hyphens before creating a result file. For example,
`Claude Sonnet 5` and `Claude-Sonnet-5` normalize to `claude-sonnet-5`.

This validation confirms that the installed CLI recognizes the identifier. The
CLI does not expose account-specific model entitlement through a non-interactive
listing command, so the runner can only confirm account availability when the
first request starts. If the account rejects the model before producing a
response, the runner removes the empty partial result and directs the operator
to the live `/model` picker.

### GitHub Copilot CLI

From a terminal inside the dev container:

```bash
mkdir -p /tmp/model-selection
cd /tmp/model-selection
copilot
```

Enter `/model` and select one of the models currently available to the signed-in
account. Note the model identifier shown by the picker, then exit the session.
Pass that identifier as the second argument to the runner:

```bash
cd /workspaces/sjov-med-it
./arduino-generation-test/scripts/run-benchmark.sh \
  copilot-cli \
  MODEL_IDENTIFIER \
  high \
  1
```

For example:

```bash
./arduino-generation-test/scripts/run-benchmark.sh \
  copilot-cli \
  gpt-5.6-sol \
  high \
  1
```

Copilot CLI also accepts `auto`, but avoid it for benchmark runs because the
resolved model can vary. Select an explicit model identifier instead.

### Claude Code

From the same isolated directory:

```bash
cd /tmp/model-selection
claude
```

Enter `/model`, choose an available model, note its alias or full identifier,
and exit. Pass that value as the second argument:

```bash
cd /workspaces/sjov-med-it
./arduino-generation-test/scripts/run-benchmark.sh \
  claude-code \
  MODEL_ALIAS_OR_IDENTIFIER \
  high \
  1
```

Claude Code commonly exposes aliases such as `sonnet`, `opus`, `haiku`,
`fable`, and `best`, depending on account availability. Aliases may resolve to
newer model versions over time. Prefer a full model identifier when comparing
results over a longer period; use an alias when testing the provider's current
recommended model.

The runner records exactly the value supplied on the command line. If an alias
is used and the resolved version is not reported by the CLI, keep
`Model version` as `Unknown` rather than guessing.

## Automated test process

For a completely clean benchmark series:

1. Delete any previous result or `.partial.md` file for the same harness,
   model, and run number.
2. In VS Code, run **Dev Containers: Rebuild Container Without Cache**.
3. Authenticate the selected CLI inside the rebuilt container. For Copilot,
   use the dedicated authentication directory shown below.
4. Run the benchmark command below.

Authentication and other container-local state are discarded by the rebuild.
The repository remains mounted, so committed files and generated result files
remain available unless you delete them explicitly.

Authenticate Copilot with:

```bash
COPILOT_HOME=$HOME/.benchmark-copilot-auth copilot login
```

Every Copilot benchmark and review copies only `config.json` from this
authentication-only directory into a fresh temporary `COPILOT_HOME`. Installed
plugins, personal skills, MCP configuration, hooks, settings, extensions,
permissions, and session history are not inherited. Do not install
customizations into `.benchmark-copilot-auth`.

Run GitHub Copilot CLI with:

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
and creates the correctly named result file. Each turn includes the exact
submitted prompt, its metrics, and the untouched response, so the result can be
read independently of `task.md`. If a turn fails, the script preserves the
content collected so far in a `.partial.md` file.

After a successful run, the same command starts a fresh isolated reviewer
session. The reviewer receives the completed result, `task.md`, and the review
template only after all seven benchmark turns have finished. It writes a
matching review with `Review status: Complete`; the benchmark conversation
never sees the expected reasoning or scores itself.

By default, the review uses the same harness and model in a new session. To use
a fixed independent reviewer model, add:

```bash
--review-model gpt-5.6-sol
```

Copilot model identifiers are validated before benchmark calls. Claude Code
does not expose a non-generating account-specific model list, so Claude runs
must use the tested model for their separate review session.

If result generation succeeds but review generation fails, the completed result
is preserved. Retry only the review without repeating the seven benchmark
turns:

```bash
bash ./arduino-generation-test/scripts/review-result.sh \
  copilot-cli \
  gpt-5.6-sol \
  ./arduino-generation-test/results/RESULT_FILE.md \
  --force
```

Each turn records:

- Wall-clock duration measured by the runner.
- CLI-reported duration when available.
- Input, output, cache-read, and cache-write tokens when reported.
- Reported cost or AI-credit usage when available.

The runner does not estimate missing usage. Unsupported or absent values are
recorded as `Unknown`. Wall-clock duration includes local CLI and network
overhead, while CLI-reported duration and token accounting follow the selected
harness's own definitions.

Copilot CLI reports cumulative session usage for resumed conversations. The
runner converts those counters to per-turn deltas. Claude Code reports
per-invocation usage directly. Copilot's `cost` value is recorded as AI
credits; Claude Code's `total_cost_usd` value is recorded as USD.

For every model process, the runner removes forwarded host tokens, Git
credential helpers, and SSH agent sockets. It also disables custom
instructions, IDE integration, memory, remote features, and model fallback
where the selected CLI provides a control. The baseline profile exposes no
custom tools, MCP servers, plugins, or skills. Non-baseline profiles expose
only their declared capability set.

Authentication is intentionally not automated. Sign in from inside the
disposable container so credentials are not forwarded from the host or stored
in the repository. Copilot authentication must use the dedicated
`.benchmark-copilot-auth` location described above.

After a successful run, inspect the automatically completed review and commit
it together with the matching result. Rebuild the container before the next
fully isolated benchmark series.
