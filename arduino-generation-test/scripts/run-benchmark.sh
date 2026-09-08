#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-benchmark.sh <copilot-cli|claude-code> <model> [effort] [run-number] [options]

Arguments:
  model        Use an identifier or display name from the CLI's live /model picker.
  effort       Defaults to medium.
  run-number   Defaults to 1.

Options:
  --profile PROFILE
               Capability profile ID. Defaults to baseline.
  --review-model MODEL
               Use MODEL for the fresh review session. Defaults to the tested model.
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
review_model=
profile=baseline

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
    --profile)
      if [[ $# -lt 2 ]]; then
        echo "--profile requires a profile ID." >&2
        exit 2
      fi
      profile=$2
      shift
      ;;
    --review-model)
      if [[ $# -lt 2 ]]; then
        echo "--review-model requires a model identifier." >&2
        exit 2
      fi
      review_model=$2
      shift
      ;;
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

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

if [[ $harness == copilot-cli ]]; then
  requested_model=$model
  requested_model_slug=$(slugify "$requested_model")
  mapfile -t recognized_models < <(
    "$executable" help config 2>/dev/null |
      awk '
        /^  `model`:/ {
          in_model_section = 1
          next
        }
        in_model_section && /^    - "/ {
          model = $0
          sub(/^    - "/, "", model)
          sub(/"$/, "", model)
          print model
          found_model = 1
          next
        }
        in_model_section && found_model {
          exit
        }
      '
  )

  if ((${#recognized_models[@]} == 0)); then
    echo "Warning: Copilot CLI did not expose its recognized model identifiers." >&2
    echo "Continuing with the model exactly as provided: $model" >&2
  else
    canonical_model=
    for recognized_model in "${recognized_models[@]}"; do
      if [[ $requested_model_slug == "$(slugify "$recognized_model")" ]]; then
        canonical_model=$recognized_model
        break
      fi
    done

    if [[ -z $canonical_model ]]; then
      echo "Copilot CLI does not recognize model '$requested_model'." >&2
      echo "Recognized model identifiers:" >&2
      printf '  %s\n' "${recognized_models[@]}" >&2
      echo "Use /model interactively to confirm which of these models your account can access." >&2
      exit 2
    fi

    model=$canonical_model
    if [[ $requested_model != "$model" ]]; then
      echo "Normalized model '$requested_model' to '$model'." >&2
    fi
  fi
fi

review_model=${review_model:-$model}

if [[ $harness == copilot-cli && ${#recognized_models[@]} -gt 0 ]]; then
  requested_review_model=$review_model
  requested_review_model_slug=$(slugify "$requested_review_model")
  canonical_review_model=

  for recognized_model in "${recognized_models[@]}"; do
    if [[ $requested_review_model_slug == "$(slugify "$recognized_model")" ]]; then
      canonical_review_model=$recognized_model
      break
    fi
  done

  if [[ -z $canonical_review_model ]]; then
    echo "Copilot CLI does not recognize review model '$requested_review_model'." >&2
    echo "Use /model interactively to select an available reviewer model." >&2
    exit 2
  fi

  review_model=$canonical_review_model
  if [[ $requested_review_model != "$review_model" ]]; then
    echo "Normalized review model '$requested_review_model' to '$review_model'." >&2
  fi
fi

if [[ $harness == claude-code ]]; then
  if [[ "$(slugify "$review_model")" != "$(slugify "$model")" ]]; then
    echo "Claude Code review must use the tested model because the CLI does not" >&2
    echo "provide a non-generating account-specific model validation command." >&2
    echo "Omit --review-model or pass the same Claude model." >&2
    exit 2
  fi
  review_model=$model
fi

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
experiment_directory=$(cd -- "$script_directory/.." && pwd)
task_path="$experiment_directory/task.md"
results_directory="$experiment_directory/results"
reviews_directory="$experiment_directory/reviews"
review_script="$script_directory/review-result.sh"
review_template="$reviews_directory/_template.md"
profile_validator="$script_directory/validate-profile.sh"
capabilities_directory="$experiment_directory/capabilities"
researcher=${BENCHMARK_RESEARCHER:-Unknown}
session_id=$(cat /proc/sys/kernel/random/uuid)
model_slug=$(slugify "$model")

if [[ -z $model_slug ]]; then
  echo "The model name must contain at least one letter or digit." >&2
  exit 2
fi

if [[ ! -f $profile_validator ]]; then
  echo "Profile validator was not found at $profile_validator." >&2
  exit 1
fi

profile_info=$(bash "$profile_validator" "$profile")
profile_id=$(jq -r '.id' <<<"$profile_info")
profile_path=$(jq -r '.path' <<<"$profile_info")
profile_hash=$(jq -r '.hash' <<<"$profile_info")
profile_slug=$(slugify "$profile_id")

if ! jq -e --arg harness "$harness" \
  '.harnesses | index($harness) != null' "$profile_path" >/dev/null; then
  echo "Capability profile '$profile_id' does not support harness '$harness'." >&2
  exit 2
fi

skills_display=$(jq -r '
  [
    .skills[],
    (.externalSkills[] | "\(.name)@\(.commit[0:12])")
  ]
  | if length == 0 then "None" else join(", ") end
' "$profile_path")
plugins_display=$(jq -r \
  'if .plugins | length == 0 then "None" else .plugins | join(", ") end' \
  "$profile_path")
mcp_servers_display=$(jq -r \
  'if .mcpServers | length == 0 then "None" else [.mcpServers[].name] | join(", ") end' \
  "$profile_path")
allowed_tools_display=$(jq -r \
  'if .allowedTools | length == 0 then "None" else .allowedTools | join(", ") end' \
  "$profile_path")
allowed_urls_display=$(jq -r \
  'if .allowedUrls | length == 0 then "None" else .allowedUrls | join(", ") end' \
  "$profile_path")
external_sources_display=$(jq -r '
  if .externalSkills | length == 0
  then "None"
  else
    [
      .externalSkills[]
      | "\(.repository)@\(.commit):\(.path) [\(.license)]"
    ]
    | join(", ")
  end
' "$profile_path")

printf -v padded_run_number '%02d' "$run_number"
if [[ $profile_id == baseline ]]; then
  run_id="${harness}-devcontainer--${model_slug}--run-${padded_run_number}"
else
  run_id="${harness}-devcontainer--${model_slug}--profile-${profile_slug}--run-${padded_run_number}"
fi
result_path="$results_directory/$run_id.md"
partial_path="$results_directory/$run_id.partial.md"
review_path="$reviews_directory/$run_id.md"
review_partial_path="$reviews_directory/$run_id.partial.md"

if [[ $force == false &&
  ( -e $result_path || -e $partial_path || -e $review_path || -e $review_partial_path ) ]]; then
  echo "A result or review already exists for $run_id. Use --force to overwrite it." >&2
  exit 1
fi

if [[ ! -f $review_script ]]; then
  echo "Review runner was not found at $review_script." >&2
  exit 1
fi

if [[ ! -f $review_template ]]; then
  echo "Review template was not found at $review_template." >&2
  exit 1
fi

work_directory=$(mktemp -d "${HOME}/arduino-benchmark.XXXXXX")
prompt_directory="$work_directory/prompts"
response_directory="$work_directory/responses"
isolated_copilot_home="$work_directory/copilot-home"
copilot_auth_home=${BENCHMARK_COPILOT_AUTH_HOME:-"$HOME/.benchmark-copilot-auth"}
mkdir -p "$prompt_directory" "$response_directory" "$results_directory" "$reviews_directory"

cleanup() {
  rm -rf -- "$work_directory"
}
trap cleanup EXIT

capability_arguments=()
external_skill_names=()
external_skill_paths=()
external_skill_identities=()
external_git_home="$work_directory/external-git-home"

prepare_isolated_copilot_home() {
  if [[ ! -f $copilot_auth_home/config.json ]]; then
    echo "Benchmark Copilot authentication was not found at $copilot_auth_home." >&2
    echo "Authenticate once inside the dev container with:" >&2
    echo "  COPILOT_HOME=\$HOME/.benchmark-copilot-auth copilot login" >&2
    exit 1
  fi

  mkdir -p "$isolated_copilot_home"
  cp "$copilot_auth_home/config.json" "$isolated_copilot_home/config.json"
  cat >"$isolated_copilot_home/settings.json" <<'EOF'
{
  "autoUpdate": false,
  "memory": false,
  "disableAllHooks": true,
  "ide.autoConnect": false
}
EOF
}

run_external_git() {
  env -i \
    HOME="$external_git_home" \
    PATH="$PATH" \
    TMPDIR="${TMPDIR:-/tmp}" \
    LANG="${LANG:-C.UTF-8}" \
    HTTPS_PROXY="${HTTPS_PROXY:-}" \
    HTTP_PROXY="${HTTP_PROXY:-}" \
    NO_PROXY="${NO_PROXY:-}" \
    https_proxy="${https_proxy:-}" \
    http_proxy="${http_proxy:-}" \
    no_proxy="${no_proxy:-}" \
    SSL_CERT_FILE="${SSL_CERT_FILE:-}" \
    SSL_CERT_DIR="${SSL_CERT_DIR:-}" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_TERMINAL_PROMPT=0 \
    git \
      -c credential.helper= \
      -c core.askPass= \
      -c core.hooksPath=/dev/null \
      -c http.extraHeader= \
      "$@"
}

resolve_external_skills() {
  local external_sources_directory="$work_directory/external-sources"
  local name
  local repository
  local commit
  local skill_path
  local license_name
  local license_path
  local checkout_directory
  local resolved_skill_path
  local resolved_license_path
  local skill_tree_hash
  local license_blob_hash

  mkdir -p "$external_sources_directory" "$external_git_home"

  while IFS=$'\t' read -r \
    name repository commit skill_path license_name license_path; do
    checkout_directory="$external_sources_directory/$name"

    run_external_git init --quiet "$checkout_directory"
    run_external_git -C "$checkout_directory" remote add origin "$repository"
    run_external_git \
      -C "$checkout_directory" \
      -c protocol.version=2 \
      fetch --quiet --depth=1 --filter=blob:none origin "$commit"
    run_external_git \
      -C "$checkout_directory" \
      -c advice.detachedHead=false \
      checkout --quiet --detach FETCH_HEAD

    if [[ $(run_external_git -C "$checkout_directory" rev-parse HEAD) != "$commit" ]]; then
      echo "External skill '$name' did not resolve to commit $commit." >&2
      exit 1
    fi

    if ! resolved_skill_path=$(realpath "$checkout_directory/$skill_path"); then
      echo "External skill '$name' path does not exist: $skill_path" >&2
      exit 1
    fi
    if ! resolved_license_path=$(realpath "$checkout_directory/$license_path"); then
      echo "External skill '$name' license path does not exist: $license_path" >&2
      exit 1
    fi
    case "$resolved_skill_path" in
      "$checkout_directory"/*)
        ;;
      *)
        echo "External skill '$name' resolves outside its checkout." >&2
        exit 1
        ;;
    esac
    case "$resolved_license_path" in
      "$checkout_directory"/*)
        ;;
      *)
        echo "External skill '$name' license resolves outside its checkout." >&2
        exit 1
        ;;
    esac

    if [[ ! -f $resolved_skill_path/SKILL.md ]]; then
      echo "External skill '$name' is missing $skill_path/SKILL.md." >&2
      exit 1
    fi
    if [[ ! -f $resolved_license_path ]]; then
      echo "External skill '$name' is missing license file $license_path." >&2
      exit 1
    fi

    skill_tree_hash=$(
      run_external_git -C "$checkout_directory" rev-parse "$commit:$skill_path"
    )
    license_blob_hash=$(
      run_external_git -C "$checkout_directory" rev-parse "$commit:$license_path"
    )

    external_skill_names+=("$name")
    external_skill_paths+=("$resolved_skill_path")
    external_skill_identities+=(
      "$repository@$commit:$skill_path:$skill_tree_hash:$license_name:$license_blob_hash"
    )
  done < <(
    jq -r '
      .externalSkills[]
      | [
          .name,
          .repository,
          .commit,
          .path,
          .license,
          .licensePath
        ]
      | @tsv
    ' "$profile_path"
  )

  if ((${#external_skill_identities[@]} > 0)); then
    profile_hash=$(
      {
        printf 'local-profile:%s\n' "$profile_hash"
        printf 'external-source:%s\n' "${external_skill_identities[@]}"
      } | sha256sum | awk '{ print $1 }'
    )
  fi
}

prepare_copilot_capabilities() {
  local generated_skill_plugin="$work_directory/profile-skills"
  local generated_mcp_config="$work_directory/profile-mcp.json"
  local skill_path
  local plugin_path
  local server_name
  local tool
  local url

  if [[ $(jq '.skills | length' "$profile_path") -gt 0 ||
    ${#external_skill_paths[@]} -gt 0 ]]; then
    mkdir -p "$generated_skill_plugin/skills"
    jq -n \
      --arg name "benchmark-profile-$profile_id" \
      --arg description "Temporary skill bundle for capability profile $profile_id." \
      '{
        name: $name,
        description: $description,
        version: "1.0.0",
        skills: ["skills/"]
      }' >"$generated_skill_plugin/plugin.json"

    while IFS= read -r skill_path; do
      cp -R \
        "$capabilities_directory/$skill_path" \
        "$generated_skill_plugin/skills/$(basename "$skill_path")"
    done < <(jq -r '.skills[]' "$profile_path")

    for index in "${!external_skill_paths[@]}"; do
      ln -s \
        "${external_skill_paths[$index]}" \
        "$generated_skill_plugin/skills/${external_skill_names[$index]}"
    done

    capability_arguments+=(--plugin-dir "$generated_skill_plugin")
  fi

  while IFS= read -r plugin_path; do
    capability_arguments+=(--plugin-dir "$capabilities_directory/$plugin_path")
  done < <(jq -r '.plugins[]' "$profile_path")

  if [[ $(jq '.mcpServers | length' "$profile_path") -gt 0 ]]; then
    jq \
      --arg root "$capabilities_directory" '
        {
          mcpServers: (
            .mcpServers
            | map({
                key: .name,
                value: {
                  type: "local",
                  command: .command,
                  args: [
                    .args[]
                    | if startswith("CAPABILITY_ROOT/")
                      then $root + "/" + ltrimstr("CAPABILITY_ROOT/")
                      else .
                      end
                  ],
                  tools: .tools
                }
              })
            | from_entries
          )
        }
      ' "$profile_path" >"$generated_mcp_config"

    capability_arguments+=(--additional-mcp-config "@$generated_mcp_config")
    while IFS= read -r server_name; do
      capability_arguments+=(--enable-mcp-server "$server_name")
    done < <(jq -r '.mcpServers[].name' "$profile_path")
  fi

  if [[ $(jq '.allowedTools | length' "$profile_path") -eq 0 ]]; then
    capability_arguments+=(--available-tools=)
  else
    while IFS= read -r tool; do
      capability_arguments+=(--available-tools="$tool")
      capability_arguments+=(--allow-tool="$tool")
    done < <(jq -r '.allowedTools[]' "$profile_path")
  fi

  while IFS= read -r url; do
    capability_arguments+=(--allow-url="$url")
  done < <(jq -r '.allowedUrls[]' "$profile_path")
}

validate_copilot_capability_loading() {
  local plugin_inventory
  local expected_plugin

  if [[ $(jq '(.skills | length) + (.externalSkills | length) + (.plugins | length)' "$profile_path") -gt 0 ]]; then
    if ! plugin_inventory=$(
      COPILOT_CUSTOM_INSTRUCTIONS_DIRS= \
      COPILOT_HOME="$isolated_copilot_home" \
        copilot "${capability_arguments[@]}" plugin list 2>&1
    ); then
      echo "Copilot CLI could not load capability profile plugins:" >&2
      printf '%s\n' "$plugin_inventory" >&2
      exit 1
    fi

    if [[ $(jq '(.skills | length) + (.externalSkills | length)' "$profile_path") -gt 0 ]]; then
      expected_plugin="benchmark-profile-$profile_id"
      if ! grep -Fq "$expected_plugin" <<<"$plugin_inventory"; then
        echo "Temporary skill plugin '$expected_plugin' was not loaded." >&2
        exit 1
      fi
    fi

    while IFS= read -r expected_plugin; do
      if ! grep -Fq "$expected_plugin" <<<"$plugin_inventory"; then
        echo "Profile plugin '$expected_plugin' was not loaded." >&2
        exit 1
      fi
    done < <(
      jq -r '.plugins[]' "$profile_path" |
        while IFS= read -r plugin_path; do
          jq -r '.name' "$capabilities_directory/$plugin_path/plugin.json"
        done
    )
  fi

}

if [[ $harness == copilot-cli ]]; then
  prepare_isolated_copilot_home
  resolve_external_skills
  prepare_copilot_capabilities
  validate_copilot_capability_loading
fi

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
  echo "Review model: $review_model"
  echo "Capability profile: $profile_id"
  echo "Profile SHA-256: $profile_hash"
  echo "Skills: $skills_display"
  echo "Plugins: $plugins_display"
  echo "MCP servers: $mcp_servers_display"
  echo "Allowed tools: $allowed_tools_display"
  echo "Allowed URLs: $allowed_urls_display"
  echo "External sources: $external_sources_display"
  echo "Run ID: $run_id"
  echo "Session ID: $session_id"
  echo "Prompts: 7"
  echo "No model calls were made."
  exit 0
fi

if [[ $force == true ]]; then
  rm -f -- "$result_path" "$partial_path" "$review_path" "$review_partial_path"
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
| Capability profile | $profile_id |
| Capability profile SHA-256 | $profile_hash |
| Skills | $skills_display |
| Plugins | $plugins_display |
| MCP servers | $mcp_servers_display |
| External capability sources | $external_sources_display |
| System/custom instructions | Built-in only; customizations disabled |
| Tools enabled | $allowed_tools_display |
| Skills or subagents enabled | Profile skills and plugins as listed; subagents disabled |
| Repository context provided | None |
| Internet access | Model API plus profile URLs: $allowed_urls_display |
| Run number | $run_number |
| Session ID | $session_id |

## Harness notes

Prompts were submitted by \`scripts/run-benchmark.sh\` from an empty directory
outside the repository. Host-forwarded tokens, Git credential helpers, and
agent sockets were removed from the model process environment. Capability
profile \`$profile_id\` was validated before the run and loaded only for the
benchmark session. The separate reviewer did not receive these capabilities.

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
    COPILOT_HOME="$isolated_copilot_home" \
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
    "${capability_arguments[@]}" \
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
    --setting-sources "" \
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

cd "$work_directory"

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
    if [[ $turn -eq 1 && $harness == copilot-cli ]] &&
      grep -Fq 'from --model flag is not available' "$error_path"; then
      cat "$error_path" >&2
      rm -f -- "$partial_path"
      echo "The model identifier is recognized by the CLI but is not available to the signed-in account." >&2
      echo "No partial result was retained because the model was rejected before the first response." >&2
      echo "Run copilot interactively and use /model to see the account's live model selection." >&2
      exit "$status"
    fi

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
  elif [[ $reported_cost_unit == "AI credits" && $reported_cost == 1 ]]; then
    reported_cost_display="1 AI credit"
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

echo "Created result: $result_path"
echo "Running isolated review..." >&2

if ! bash "$review_script" \
  "$harness" \
  "$review_model" \
  "$result_path"; then
  echo "The benchmark result is complete, but automated review failed." >&2
  echo "Retry only the review with:" >&2
  printf '  bash %q %q %q %q --force\n' \
    "$review_script" "$harness" "$review_model" "$result_path" >&2
  exit 1
fi

echo "Created completed review: $review_path"
