# Repository instructions

## Architecture

This repository is a collection of independent group experiments. The root
`README.md` is the experiment index; each experiment lives in a self-contained
top-level directory with its own task definition, raw results, and reviews.
When adding an experiment, add it to the root experiment table without
coupling its files to another experiment.

`arduino-generation-test/` is a progressive conversational benchmark:

- `task.md` is the source of truth for the seven prompts, expected reasoning,
  and eight-point evaluation rubric.
- `results/` contains complete, unchanged transcripts and run metadata.
- `reviews/` contains human scoring and analysis, separate from raw output.
- Matching result and review files represent one run of a specific harness and
  model combination.

The model and harness are independent benchmark dimensions. The model is the
underlying language model; the harness is the client, agent, CLI, IDE, or API
integration that supplies context, instructions, tools, and execution
behavior.

## Benchmark conventions

- Preserve the wording, spelling, punctuation, and order of all prompts in
  `arduino-generation-test/task.md`.
- Run all seven prompts in one clean session. Do not reveal the expected
  reasoning or evaluation criteria to the model under test.
- Never correct, reformat, summarize, or otherwise alter content copied into a
  result file. Put interpretations and corrections in the matching review.
- Create results from `results/_template.md` and reviews from
  `reviews/_template.md`.
- Name paired files
  `harness--model--run-NN.md`, for example
  `copilot-cli--gpt-5-6-sol--run-01.md`.
- Record unavailable metadata as `Unknown`. Use `Default` or `Not available`
  for inaccessible system instructions; do not attempt to extract them.
- Record harness behavior that could influence a run, including repository
  context, custom instructions, tools, skills, subagents, internet access,
  automatic file or command actions, retries, and response post-processing.
- Score each review with only `0` or `1` per criterion and include a turn
  reference or quotation when a score is ambiguous.
- Keep raw results and human reviews separate even when adding generated
  summaries or a future static report.

## Sensitive content

Before committing benchmark data, remove credentials, private system
instructions, unrelated private repository content, and personal data. Preserve
the tested response otherwise; document any required redaction explicitly in
the run notes.

## Documentation changes

Keep Markdown concise and use relative links within the repository. When an
experiment is added or its status changes, update both its local `README.md`
and the root experiment table when applicable.
