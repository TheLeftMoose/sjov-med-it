# Agent instructions

## Repository architecture

This repository contains independent group experiments. The root `README.md`
indexes them, and each experiment belongs in a self-contained top-level
directory with its own task definition, raw results, and reviews.

`arduino-generation-test/` is a progressive conversational benchmark:

- `task.md` defines the seven prompts, expected reasoning, and scoring rubric.
- `results/` stores complete, unchanged transcripts and run metadata.
- `reviews/` stores human evaluation separately from raw model output.
- Matching result and review files represent one run of a particular harness
  and model combination.

Treat the model and harness as separate dimensions. The model is the underlying
language model. The harness is the client, agent, CLI, IDE, or API integration
that supplies instructions, context, tools, and execution behavior.

## Development container

Use the root `.devcontainer/` configuration for clean CLI benchmark
environments. It installs GitHub Copilot CLI through the official Dev Container
Feature and Claude Code through Anthropic's native installer; do not replace
the Claude installation with its Dev Container Feature because that feature
uses the public npm registry.

The CLI versions are pinned in `.devcontainer/devcontainer.json` and
`.devcontainer/Dockerfile`. When changing either version, update the root
`README.md` and record the exact runtime version in new benchmark results.

The container intentionally does not mount host AI-tool configuration or
credentials. Do not add mounts for `~/.copilot`, `~/.claude`, `~/.agents`, MCP
configuration, plugins, skills, SSH keys, or cloud credentials. Authenticate
inside the container or provide short-lived credentials at runtime without
committing them.

Verify the installed tools inside the container with:

```bash
copilot --version
claude --version
```

## Benchmark conventions

- Preserve the exact wording, spelling, punctuation, and order of prompts in
  `arduino-generation-test/task.md`.
- Run all prompts in one clean session without showing the expected reasoning
  or rubric to the model under test.
- Do not correct, reformat, summarize, or otherwise alter raw responses.
  Record interpretations and corrections in the matching review.
- Create result and review files from their respective `_template.md` files.
- Name paired files `harness--model--run-NN.md`.
- Use `Unknown` for unavailable metadata. Use `Default` or `Not available` for
  inaccessible system instructions; never attempt to extract them.
- Record harness features that may influence output, including repository
  context, custom instructions, tools, skills, subagents, internet access,
  automatic actions, retries, and post-processing.
- Score reviews with only `0` or `1` per criterion. Cite the relevant turn or
  response text when a score is ambiguous.
- Keep raw results and human reviews separate from generated summaries and
  future report files.

## Sensitive content

Remove credentials, private system instructions, unrelated private repository
content, and personal data before committing benchmark data. Otherwise preserve
the response exactly and document any necessary redaction in the run notes.

## Documentation

Keep Markdown concise and use relative repository links. When adding an
experiment or changing its status, update its local `README.md` and the root
experiment table where applicable.
