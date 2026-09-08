#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-benchmark.sh <copilot-cli|claude-code> <model> [effort] [run-number] [options]

Arguments:
  effort       Defaults to medium.
  run-number   Defaults to 1.

Options:
  --dry-run    Validate the setup without making model calls.
  --force      Overwrite an existing result or partial result.
  --help       Show this help.

Set BENCHMARK_RESEARCHER to include a researcher name in the result metadata.
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

if [[ $force == false && ( -e $result_path || -e $partial_path ) ]]; then
  echo "A result already exists for $run_id. Use --force to overwrite it." >&2
  exit 1
fi

work_directory=$(mktemp -d "${HOME}/arduino-benchmark.XXXXXX")
prompt_directory="$work_directory/prompts"
response_directory="$work_directory/responses"
mkdir -p "$prompt_directory" "$response_directory" "$results_directory"

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
  rm -f -- "$result_path" "$partial_path"
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
    --stream off
}

run_claude_turn() {
  local turn=$1
  local prompt=$2
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
    --output-format text \
    "$prompt"
}

for turn in {1..7}; do
  echo "Running turn $turn of 7..." >&2
  prompt=$(cat "$prompt_directory/turn-$turn.txt")
  response_path="$response_directory/turn-$turn.txt"
  error_path="$response_directory/turn-$turn.error.txt"

  set +e
  if [[ $harness == copilot-cli ]]; then
    run_copilot_turn "$prompt" >"$response_path" 2>"$error_path"
  else
    run_claude_turn "$turn" "$prompt" >"$response_path" 2>"$error_path"
  fi
  status=$?
  set -e

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

  {
    printf '\n## Turn %s response\n\n' "$turn"
    cat "$response_path"
    printf '\n'
  } >>"$partial_path"
done

sed -i \
  's/Run is in progress. If this file retains the `.partial.md` suffix, the run did/None. The run completed without a harness error./' \
  "$partial_path"
sed -i \
  '/^not complete\.$/d' \
  "$partial_path"

mv -- "$partial_path" "$result_path"
echo "Created result: $result_path"
