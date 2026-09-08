#!/usr/bin/env bash
set -u

send_error() {
  local request_id=$1
  local message=$2

  jq -cn \
    --argjson id "$request_id" \
    --arg message "$message" \
    '{jsonrpc:"2.0", id:$id, error:{code:-32601, message:$message}}'
}

while IFS= read -r request; do
  if ! method=$(jq -er '.method' <<<"$request" 2>/dev/null); then
    jq -cn \
      '{jsonrpc:"2.0", id:null, error:{code:-32700, message:"Invalid JSON-RPC request"}}'
    continue
  fi

  request_id=$(jq -c '.id // null' <<<"$request")

  case "$method" in
    initialize)
      protocol_version=$(
        jq -r '.params.protocolVersion // "2025-03-26"' <<<"$request"
      )
      jq -cn \
        --argjson id "$request_id" \
        --arg protocolVersion "$protocol_version" \
        '{
          jsonrpc:"2.0",
          id:$id,
          result:{
            protocolVersion:$protocolVersion,
            capabilities:{tools:{}},
            serverInfo:{name:"arduino-guidance", version:"1.0.0"}
          }
        }'
      ;;
    notifications/initialized)
      ;;
    ping)
      jq -cn --argjson id "$request_id" \
        '{jsonrpc:"2.0", id:$id, result:{}}'
      ;;
    tools/list)
      jq -cn --argjson id "$request_id" '
        {
          jsonrpc:"2.0",
          id:$id,
          result:{
            tools:[
              {
                name:"explain_arduino_constraints",
                description:"Explain the distinction between toggling an Arduino output state and controlling elapsed time.",
                inputSchema:{
                  type:"object",
                  properties:{
                    pin:{
                      type:"integer",
                      description:"Arduino digital pin number.",
                      default:13
                    }
                  },
                  additionalProperties:false
                }
              }
            ]
          }
        }
      '
      ;;
    tools/call)
      tool_name=$(jq -r '.params.name // ""' <<<"$request")
      if [[ $tool_name != explain_arduino_constraints ]]; then
        send_error "$request_id" "Unknown tool"
        continue
      fi

      pin=$(jq -r '.params.arguments.pin // 13' <<<"$request")
      guidance="For pin $pin, digitalWrite($pin, !digitalRead($pin)) toggles the current boolean state once per execution. The modulus equivalent is digitalWrite($pin, (digitalRead($pin) + 1) % 2). Neither expression measures time. When called directly from loop(), other work changes the loop duration and therefore the toggle frequency. Without a delay, clock, timer, state variable, or another predictable time source, an approximately one-second interval cannot be guaranteed."
      jq -cn \
        --argjson id "$request_id" \
        --arg guidance "$guidance" \
        '{
          jsonrpc:"2.0",
          id:$id,
          result:{
            content:[{type:"text", text:$guidance}],
            isError:false
          }
        }'
      ;;
    *)
      if [[ $request_id != null ]]; then
        send_error "$request_id" "Method not found"
      fi
      ;;
  esac
done
