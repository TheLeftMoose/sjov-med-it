#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-benchmark.sh <copilot-cli|claude-code> <model> [effort] [run-number] [options]

Arguments:
  model        Use an identifier from the CLI's live /model picker.
  effort       Defaults to medium.
  run-number   Defaults to 1.

Options:
  --dry-run    Validate the setup without making model calls.
  --force      Overwrite an existing result or partial result.
  --help       Show this help.

Set BENCHMARK_RESEARCHER to include a researcher name in the result metadata.
Avoid Copilot's auto model selection for comparable benchmark runs.
EOF
}

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi

harness=$1
model=$2
shift 2

effort=medium
run_number=1
force=false
dry_run=false

if [[ $# -gt 0 && $1 != --* ]]; then
  effort=$1
  shift
fi

if [[ $# -gt 0 && $1 != --* ]]; then
  run_number=$1
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      ;;
    --force)
      force=true
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$harness" in
  copilot-cli)
    executable=copilot
    harness_name="GitHub Copilot CLI"
    provider="GitHub Copilot"
    ;;
  claude-code)
    executable=claude
    harness_name="Claude Code"
    provider="Anthropic"
    ;;
  *)
    echo "Unsupported harness: $harness" >&2
    exit 2
    ;;
esac

if [[ ! $run_number =~ ^[0-9]+$ ]] || ((run_number < 1 || run_number > 99)); then
  echo "Run number must be between 1 and 99." >&2
  exit 2
fi

case "$harness:$effort" in
  copilot-cli:none|copilot-cli:minimal|copilot-cli:low|copilot-cli:medium|copilot-cli:high|copilot-cli:xhigh|copilot-cli:max)
    ;;
  claude-code:low|claude-code:medium|claude-code:high|claude-code:xhigh|claude-code:max)
    ;;
  *)
    echo "Unsupported effort '$effort' for $harness." >&2
    exit 2
    ;;
esac

if ! command -v "$executable" >/dev/null 2>&1; then
  echo "$executable was not found on PATH." >&2
  exit 1
fi

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
experiment_directory=$(cd -- "$script_directory/.." && pwd)
task_path="$experiment_directory/task.md"
results_directory="$experiment_directory/results"
reviews_directory="$experiment_directory/reviews"
review_template="$reviews_directory/_template.md"
researcher=${BENCHMARK_RESEARCHER:-Unknown}
session_id=$(cat /proc/sys/kernel/random/uuid)
model_slug=$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')

if [[ -z $model_slug ]]; then
  echo "The model name must contain at least one letter or digit." >&2
  exit 2
fi

printf -v padded_run_number '%02d' "$run_number"
run_id="${harness}-devcontainer--${model_slug}--run-${padded_run_number}"
result_path="$results_directory/$run_id.md"
partial_path="$results_directory/$run_id.partial.md"
review_path="$reviews_directory/$run_id.md"

if [[ $force == false && ( -e $result_path || -e $partial_path || -e $review_path ) ]]; then
  echo "A result or review already exists for $run_id. Use --force to overwrite it." >&2
  exit 1
fi

work_directory=$(mktemp -d "${HOME}/arduino-benchmark.XXXXXX")
prompt_directory="$work_directory/prompts"
response_directory="$work_directory/responses"
mkdir -p "$prompt_directory" "$response_directory" "$results_directory" "$reviews_directory"

cleanup() {
  rm -rf -- "$work_directory"
}
trap cleanup EXIT

awk -v output="$prompt_directory" '
  {
    sub(/\r$/, "")
  }
  /^## Prompts[[:space:]]*$/ {
    active = 1
    next
  }
  /^## Expected reasoning[[:space:]]*$/ {
    exit
  }
  active && /^### Turn [0-9]+[[:space:]]*$/ {
    turn = $3
    next
  }
  active && turn && /^>/ {
    line = $0
    sub(/^>[[:space:]]?/, "", line)
    print line >> (output "/turn-" turn ".txt")
  }
' "$task_path"

for turn in {1..7}; do
  prompt_path="$prompt_directory/turn-$turn.txt"
  if [[ ! -s $prompt_path ]]; then
    echo "Expected seven non-empty prompts in $task_path; turn $turn is missing." >&2
    exit 1
  fi
done

harness_version=$("$executable" --version | head -n 1)
run_started_ms=$(date +%s%3N)

if [[ $dry_run == true ]]; then
  echo "Harness: $harness_name"
  echo "Version: $harness_version"
  echo "Model: $model"
  echo "Effort: $effort"
  echo "Run ID: $run_id"
  echo "Session ID: $session_id"
  echo "Prompts: 7"
  echo "No model calls were made."
  exit 0
fi

if [[ $force == true ]]; then
  rm -f -- "$result_path" "$partial_path" "$review_path"
fi

cat >"$partial_path" <<EOF
# Benchmark run

## Metadata

| Field | Value |
| --- | --- |
| Run ID | $run_id |
| Date | $(date -u +%F) |
| Researcher | $researcher |
| Harness | $harness_name in dev container |
| Harness version | $harness_version |
| Harness mode | Automated non-interactive resumed session |
| Model provider | $provider |
| Model | $model |
| Model version | Unknown |
| Temperature | Unknown |
| Reasoning mode | $effort |
| System/custom instructions | Built-in only; customizations disabled |
| Tools enabled | None |
| Skills or subagents enabled | Custom capabilities disabled; harness built-ins may remain |
| Repository context provided | None |
| Internet access | Model API only; no web tools |
| Run number | $run_number |
| Session ID | $session_id |

## Harness notes

Prompts were submitted by \`scripts/run-benchmark.sh\` from an empty directory
outside the repository. Host-forwarded tokens, Git credential helpers, and
agent sockets were removed from the model process environment.

## Run notes

Run is in progress. If this file retains the \`.partial.md\` suffix, the run did
not complete.
EOF

run_sanitized() {
  env \
    -u ANTHROPIC_API_KEY \
    -u CLAUDE_CODE_OAUTH_TOKEN \
    -u COPILOT_GITHUB_TOKEN \
    -u GH_TOKEN \
    -u GITHUB_TOKEN \
    -u SSH_AUTH_SOCK \
    -u GIT_ASKPASS \
    -u SSH_ASKPASS \
    -u VSCODE_GIT_ASKPASS_EXTRA_ARGS \
    -u VSCODE_GIT_ASKPASS_MAIN \
    -u VSCODE_GIT_ASKPASS_NODE \
    COPILOT_CUSTOM_INSTRUCTIONS_DIRS= \
    "$@"
}

run_copilot_turn() {
  local prompt=$1
  local usage_path=$2

  run_sanitized copilot \
    --prompt "$prompt" \
    --session-id "$session_id" \
    --model "$model" \
    --reasoning-effort "$effort" \
    --no-custom-instructions \
    --disable-builtin-mcps \
    --disallow-temp-dir \
    --available-tools= \
    --allow-all-tools \
    --silent \
    --no-color \
    --no-auto-update \
    --no-remote \
    --no-remote-export \
    --usage-output-file "$usage_path" \
    --stream off
}

run_claude_turn() {
  local turn=$1
  local prompt=$2
  local usage_path=$3
  local -a session_arguments

  if [[ $turn -eq 1 ]]; then
    session_arguments=(--session-id "$session_id")
  else
    session_arguments=(--resume "$session_id")
  fi

  run_sanitized claude \
    --print \
    "${session_arguments[@]}" \
    --model "$model" \
    --effort "$effort" \
    --safe-mode \
    --restricted \
    --strict-mcp-config \
    --mcp-config '{"mcpServers":{}}' \
    --tools "" \
    --disable-slash-commands \
    --permission-mode dontAsk \
    --permission-prompts none \
    --no-chrome \
    --output-format json \
    "$prompt" >"$usage_path"
}

json_sum() {
  local path=$1
  local key_pattern=$2

  if [[ ! -s $path ]]; then
    printf 'Unknown'
    return
  fi

  jq -r --arg pattern "$key_pattern" '
    [
      paths(scalars) as $path
      | select(($path[-1] | tostring) | test($pattern; "i"))
      | getpath($path)
      | numbers
    ]
    | if length == 0 then "Unknown" else add end
  ' "$path" 2>/dev/null || printf 'Unknown'
}

json_first() {
  local path=$1
  local key_pattern=$2

  if [[ ! -s $path ]]; then
    printf 'Unknown'
    return
  fi

  jq -r --arg pattern "$key_pattern" '
    [
      paths(scalars) as $path
      | select(($path[-1] | tostring) | test($pattern; "i"))
      | getpath($path)
    ]
    | if length == 0 then "Unknown" else first end
  ' "$path" 2>/dev/null || printf 'Unknown'
}

subtract_values() {
  local current=$1
  local previous=$2

  if [[ $current == Unknown || $previous == Unknown ]]; then
    printf 'Unknown'
    return
  fi

  awk -v current="$current" -v previous="$previous" \
    'BEGIN { print current - previous }'
}

previous_input_tokens=0
previous_output_tokens=0
previous_cache_read_tokens=0
previous_cache_write_tokens=0
previous_cost=0
previous_cli_duration_ms=0

for turn in {1..7}; do
  echo "Running turn $turn of 7..." >&2
  prompt=$(cat "$prompt_directory/turn-$turn.txt")
  response_path="$response_directory/turn-$turn.txt"
  error_path="$response_directory/turn-$turn.error.txt"
  usage_path="$response_directory/turn-$turn.usage.json"
  turn_started_ms=$(date +%s%3N)

  set +e
  if [[ $harness == copilot-cli ]]; then
    run_copilot_turn "$prompt" "$usage_path" >"$response_path" 2>"$error_path"
  else
    run_claude_turn "$turn" "$prompt" "$usage_path" 2>"$error_path"
  fi
  status=$?
  set -e
  turn_finished_ms=$(date +%s%3N)
  turn_duration_ms=$((turn_finished_ms - turn_started_ms))

  if [[ $status -ne 0 ]]; then
    {
      printf '\n## Run failure\n\n'
      printf 'Turn %s exited with status %s.\n\n' "$turn" "$status"
      printf '```text\n'
      cat "$error_path"
      printf '\n```\n'
    } >>"$partial_path"
    cat "$error_path" >&2
    echo "Partial result retained at $partial_path" >&2
    exit "$status"
  fi

  if [[ $harness == claude-code ]]; then
    if ! jq -e '.result | strings' "$usage_path" >/dev/null 2>&1; then
      echo "Claude Code did not return the expected JSON result for turn $turn." >&2
      exit 1
    fi
    jq -j '.result' "$usage_path" >"$response_path"
  fi

  if [[ $harness == claude-code ]]; then
    input_tokens=$(jq -r '.usage.input_tokens // "Unknown"' "$usage_path")
    output_tokens=$(jq -r '.usage.output_tokens // "Unknown"' "$usage_path")
    cache_read_tokens=$(jq -r '.usage.cache_read_input_tokens // "Unknown"' "$usage_path")
    cache_write_tokens=$(jq -r '.usage.cache_creation_input_tokens // "Unknown"' "$usage_path")
    cli_duration_ms=$(jq -r '.duration_ms // "Unknown"' "$usage_path")
    reported_cost=$(jq -r '.total_cost_usd // "Unknown"' "$usage_path")
    reported_cost_unit=USD
  else
    cumulative_input_tokens=$(json_sum "$usage_path" '^(input_tokens|inputTokens)$')
    cumulative_output_tokens=$(json_sum "$usage_path" '^(output_tokens|outputTokens)$')
    cumulative_cache_read_tokens=$(json_sum "$usage_path" '^(cache_read_input_tokens|cacheReadTokens|cache_read_tokens)$')
    cumulative_cache_write_tokens=$(json_sum "$usage_path" '^(cache_creation_input_tokens|cacheWriteTokens|cache_write_tokens)$')
    cumulative_cost=$(json_first "$usage_path" '^(cost|costUsd|total_cost_usd)$')

    input_tokens=$(subtract_values "$cumulative_input_tokens" "$previous_input_tokens")
    output_tokens=$(subtract_values "$cumulative_output_tokens" "$previous_output_tokens")
    cache_read_tokens=$(subtract_values "$cumulative_cache_read_tokens" "$previous_cache_read_tokens")
    cache_write_tokens=$(subtract_values "$cumulative_cache_write_tokens" "$previous_cache_write_tokens")
    reported_cost=$(subtract_values "$cumulative_cost" "$previous_cost")

    previous_input_tokens=$cumulative_input_tokens
    previous_output_tokens=$cumulative_output_tokens
    previous_cache_read_tokens=$cumulative_cache_read_tokens
    previous_cache_write_tokens=$cumulative_cache_write_tokens
    previous_cost=$cumulative_cost

    cumulative_cli_duration_ms=$(json_first "$usage_path" '^(duration_ms|durationMs)$')
    cli_duration_ms=$(subtract_values "$cumulative_cli_duration_ms" "$previous_cli_duration_ms")
    previous_cli_duration_ms=$cumulative_cli_duration_ms
    reported_cost_unit="AI credits"
  fi

  if [[ $reported_cost == Unknown ]]; then
    reported_cost_display=Unknown
  else
    reported_cost_display="$reported_cost $reported_cost_unit"
  fi

  {
    printf '\n## Turn %s prompt\n\n' "$turn"
    while IFS= read -r prompt_line || [[ -n $prompt_line ]]; do
      printf '> %s\n' "$prompt_line"
    done <"$prompt_directory/turn-$turn.txt"
    printf '\n## Turn %s metrics\n\n' "$turn"
    printf '| Metric | Value |\n'
    printf '| --- | ---: |\n'
    printf '| Wall-clock duration | %s ms |\n' "$turn_duration_ms"
    printf '| CLI-reported duration | %s |\n' "$cli_duration_ms"
    printf '| Input tokens | %s |\n' "$input_tokens"
    printf '| Output tokens | %s |\n' "$output_tokens"
    printf '| Cache-read tokens | %s |\n' "$cache_read_tokens"
    printf '| Cache-write tokens | %s |\n' "$cache_write_tokens"
    printf '| Reported cost | %s |\n' "$reported_cost_display"
    printf '\n## Turn %s response\n\n' "$turn"
    cat "$response_path"
    printf '\n'
  } >>"$partial_path"
done

run_finished_ms=$(date +%s%3N)
run_duration_ms=$((run_finished_ms - run_started_ms))

sed -i \
  's/Run is in progress. If this file retains the `.partial.md` suffix, the run did/None. The run completed without a harness error./' \
  "$partial_path"
sed -i \
  '/^not complete\.$/d' \
  "$partial_path"
sed -i \
  "/| Session ID |/a | Total wall-clock duration | ${run_duration_ms} ms |" \
  "$partial_path"

mv -- "$partial_path" "$result_path"
awk \
  -v result="../results/$run_id.md" \
  -v harness="$harness_name in dev container" \
  -v model="$model" \
  -v review_date="$(date -u +%F)" '
    /^Link to result:/ {
      print "Link to result: [`" result "`](" result ")"
      next
    }
    /^Harness:/ {
      print "Harness: " harness
      next
    }
    /^Model:/ {
      print "Model: `" model "`"
      next
    }
    /^Review date:/ {
      print "Review date: " review_date
      next
    }
    { print }
  ' "$review_template" >"$review_path"

echo "Created result: $result_path"
echo "Created pending review: $review_path"
