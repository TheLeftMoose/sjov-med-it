#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: validate-profile.sh <profile-id-or-path>" >&2
  exit 2
fi

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
experiment_directory=$(cd -- "$script_directory/.." && pwd)
capabilities_directory="$experiment_directory/capabilities"
profile_input=$1

if [[ $profile_input == */* || $profile_input == *.json ]]; then
  profile_path=$profile_input
else
  profile_path="$capabilities_directory/profiles/$profile_input.json"
fi

if [[ ! -f $profile_path ]]; then
  echo "Capability profile was not found: $profile_path" >&2
  exit 1
fi

profile_path=$(realpath "$profile_path")
profiles_directory=$(realpath "$capabilities_directory/profiles")

case "$profile_path" in
  "$profiles_directory"/*.json)
    ;;
  *)
    echo "Profiles must be JSON files inside $profiles_directory." >&2
    exit 1
    ;;
esac

if ! jq -e '
  type == "object"
  and ((keys - [
    "schemaVersion",
    "id",
    "description",
    "harnesses",
    "skills",
    "plugins",
    "mcpServers",
    "allowedTools",
    "allowedUrls"
  ]) | length == 0)
  and .schemaVersion == 1
  and (.id | type == "string" and test("^[a-z0-9]+(?:-[a-z0-9]+)*$"))
  and (.description | type == "string" and length > 0)
  and (.harnesses | type == "array" and length > 0)
  and all(.harnesses[]; . == "copilot-cli" or . == "claude-code")
  and (.skills | type == "array" and all(.[]; type == "string"))
  and (.plugins | type == "array" and all(.[]; type == "string"))
  and (.mcpServers | type == "array")
  and all(.mcpServers[];
    type == "object"
    and ((keys - ["name", "command", "args", "tools"]) | length == 0)
    and (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_-]*$"))
    and (.command | type == "string" and length > 0)
    and (.args | type == "array" and all(.[]; type == "string"))
    and (.tools | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
  )
  and ([.mcpServers[].name] | length == (unique | length))
  and (.allowedTools | type == "array" and all(.[]; type == "string" and length > 0))
  and (
    (.allowedTools | sort)
    == (
      [
        .mcpServers[] as $server
        | $server.tools[]
        | ($server.name + "(" + . + ")")
      ]
      | sort
    )
  )
  and (.allowedUrls | type == "array" and all(.[]; type == "string" and test("^https?://")))
' "$profile_path" >/dev/null; then
  echo "Invalid capability profile schema: $profile_path" >&2
  exit 1
fi

profile_id=$(jq -r '.id' "$profile_path")
if [[ $(basename "$profile_path") != "$profile_id.json" ]]; then
  echo "Profile filename must match its id: $profile_id.json" >&2
  exit 1
fi

resolve_capability_path() {
  local relative_path=$1
  local resolved_path

  resolved_path=$(realpath -m "$capabilities_directory/$relative_path")
  case "$resolved_path" in
    "$capabilities_directory"/*)
      printf '%s' "$resolved_path"
      ;;
    *)
      echo "Capability path escapes $capabilities_directory: $relative_path" >&2
      return 1
      ;;
  esac
}

referenced_files=("$profile_path")

while IFS= read -r skill_path; do
  resolved_skill=$(resolve_capability_path "$skill_path")
  if [[ ! -f $resolved_skill/SKILL.md ]]; then
    echo "Skill is missing SKILL.md: $skill_path" >&2
    exit 1
  fi
  while IFS= read -r file; do
    referenced_files+=("$file")
  done < <(find "$resolved_skill" -type f -print | sort)
done < <(jq -r '.skills[]' "$profile_path")

while IFS= read -r plugin_path; do
  resolved_plugin=$(resolve_capability_path "$plugin_path")
  if [[ ! -f $resolved_plugin/plugin.json ]]; then
    echo "Plugin is missing plugin.json: $plugin_path" >&2
    exit 1
  fi
  if ! jq -e '
    type == "object"
    and (.name | type == "string" and test("^[a-z0-9]+(?:-[a-z0-9]+)*$"))
  ' "$resolved_plugin/plugin.json" >/dev/null; then
    echo "Plugin manifest is invalid: $plugin_path/plugin.json" >&2
    exit 1
  fi
  while IFS= read -r file; do
    referenced_files+=("$file")
  done < <(find "$resolved_plugin" -type f -print | sort)
done < <(jq -r '.plugins[]' "$profile_path")

while IFS= read -r argument; do
  if [[ $argument == CAPABILITY_ROOT/* ]]; then
    relative_path=${argument#CAPABILITY_ROOT/}
    resolved_argument=$(resolve_capability_path "$relative_path")
    if [[ ! -f $resolved_argument ]]; then
      echo "MCP argument file does not exist: $argument" >&2
      exit 1
    fi
    referenced_files+=("$resolved_argument")
  fi
done < <(jq -r '.mcpServers[].args[]' "$profile_path")

profile_hash=$(
  {
    for file in "${referenced_files[@]}"; do
      relative_file=${file#"$capabilities_directory/"}
      printf '%s  ' "$relative_file"
      sha256sum "$file" | awk '{ print $1 }'
    done
  } | sort -u | sha256sum | awk '{ print $1 }'
)

jq -n \
  --arg id "$profile_id" \
  --arg path "$profile_path" \
  --arg hash "$profile_hash" \
  '{
    id: $id,
    path: $path,
    hash: $hash
  }'
