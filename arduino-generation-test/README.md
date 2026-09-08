# Arduino generation test

This experiment compares how different models respond to a progressively
constrained Arduino code-generation task.

The task begins as a simple request to blink an LED on pin 13. Each subsequent
message removes an implementation option or introduces a new hint. The test is
intended to evaluate context retention, constraint handling, code reasoning,
and whether the model recognizes when the complete set of requirements cannot
guarantee the requested timing.

## Running the experiment

1. Start a new conversation with the model.
2. Record the model name, version, settings, and date in a copy of
   [`results/_template.md`](results/_template.md).
3. Send the seven prompts from [`task.md`](task.md) in order.
4. Do not reset the conversation or provide additional hints.
5. Copy each response into the result file without correcting or reformatting
   it.
6. Evaluate the responses using a copy of
   [`reviews/_template.md`](reviews/_template.md).

Use matching filenames for a result and its review:

```text
results/model-name.md
reviews/model-name.md
```

If the same model is tested more than once, append a run number:

```text
results/model-name-run-01.md
reviews/model-name-run-01.md
```

## Fairness rules

- Use a clean conversation for each run.
- Use the prompts exactly as written.
- Keep model output unchanged, including mistakes.
- Record unknown model settings as `Unknown`.
- Do not expose the expected reasoning or review criteria to the model.
- Note interruptions, retries, or tool use in the result metadata.
