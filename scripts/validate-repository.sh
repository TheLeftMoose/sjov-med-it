#!/usr/bin/env bash
set -Eeuo pipefail

bash -n \
  arduino-generation-test/scripts/run-benchmark.sh \
  arduino-generation-test/scripts/review-result.sh \
  arduino-generation-test/scripts/validate-profile.sh \
  arduino-generation-test/capabilities/mcp/arduino-guidance.sh \
  scripts/validate-repository.sh
jq empty .devcontainer/devcontainer.json .devcontainer/devcontainer-lock.json

for profile in arduino-generation-test/capabilities/profiles/*.json; do
  bash arduino-generation-test/scripts/validate-profile.sh "$profile" >/dev/null
done

for plugin in arduino-generation-test/capabilities/plugins/*/plugin.json; do
  jq empty "$plugin"
done

result_directory=arduino-generation-test/results
review_directory=arduino-generation-test/reviews

for result in "$result_directory"/*.md; do
  name=$(basename "$result")
  [[ $name == "_template.md" || $name == *.partial.md ]] && continue

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

  if ! grep -Eq '^\| Capability profile \| .+ \|$' \
    < <(tr -d '\r' <"$result"); then
    echo "$result must identify its capability profile." >&2
    exit 1
  fi

  if ! grep -Eq \
    '^\| Capability profile SHA-256 \| [a-f0-9]{64} \|$' \
    < <(tr -d '\r' <"$result"); then
    case "$name" in
      copilot-cli-devcontainer--gpt-5-6-sol--run-01.md | \
        copilot-cli-devcontainer--gpt-5-6-sol--run-02.md | \
        copilot-cli-devcontainer--claude-sonnet-5--run-01.md)
        if ! grep -Fxq \
          '| Capability profile SHA-256 | Not recorded (legacy run) |' \
          < <(tr -d '\r' <"$result"); then
          echo "$result has invalid legacy capability provenance." >&2
          exit 1
        fi
        ;;
      *)
        echo "$result must record a capability profile SHA-256." >&2
        exit 1
        ;;
    esac
  fi

  if ! grep -Fxq 'Review status: Complete' < <(tr -d '\r' <"$review"); then
    echo "$review must have Review status: Complete." >&2
    exit 1
  fi
done

for review in "$review_directory"/*.md; do
  name=$(basename "$review")
  [[ $name == "_template.md" || $name == *.partial.md ]] && continue

  result="$result_directory/$name"

  if [[ ! -f $result ]]; then
    echo "Missing result for $review" >&2
    exit 1
  fi
done
