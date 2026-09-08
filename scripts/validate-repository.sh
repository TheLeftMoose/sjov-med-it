#!/usr/bin/env bash
set -Eeuo pipefail

bash -n arduino-generation-test/scripts/run-benchmark.sh
jq empty .devcontainer/devcontainer.json .devcontainer/devcontainer-lock.json

result_directory=arduino-generation-test/results
review_directory=arduino-generation-test/reviews

for result in "$result_directory"/*.md; do
  [[ $(basename "$result") == "_template.md" ]] && continue

  name=$(basename "$result")
  review="$review_directory/$name"

  if [[ ! -f $review ]]; then
    echo "Missing review for $result" >&2
    exit 1
  fi

  if [[ $(tr -d '\r' <"$result" | grep -Ec '^## Turn [1-7] prompt$') -ne 7 ]]; then
    echo "$result must contain seven prompts." >&2
    exit 1
  fi

  if [[ $(tr -d '\r' <"$result" | grep -Ec '^## Turn [1-7] response$') -ne 7 ]]; then
    echo "$result must contain seven responses." >&2
    exit 1
  fi

  if ! tr -d '\r' <"$review" | grep -Fxq 'Review status: Complete'; then
    echo "$review must have Review status: Complete." >&2
    exit 1
  fi
done

for review in "$review_directory"/*.md; do
  [[ $(basename "$review") == "_template.md" ]] && continue

  name=$(basename "$review")
  result="$result_directory/$name"

  if [[ ! -f $result ]]; then
    echo "Missing result for $review" >&2
    exit 1
  fi
done
