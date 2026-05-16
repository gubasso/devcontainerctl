# shellcheck shell=bash

[[ -n ${_DCTL_LIB_JSON_VALIDATE_LAYER_LOADED:-} ]] && return 0
readonly _DCTL_LIB_JSON_VALIDATE_LAYER_LOADED=1

_validate_devcontainer_layer() {
  local layer_path="$1"
  local layer_json="$2"
  local key runtime_value
  # Allowlist tracks the Microsoft devcontainer.json schema (general dev
  # container properties + non-compose properties) plus dctl's `runtime` key.
  # See https://containers.dev/implementors/json_reference/ - keys present in
  # spec-conformant configs must not error here even when dctl ignores them at
  # runtime.
  local -A allowed_keys=(
    [name]=1
    [image]=1
    [build]=1
    [entrypoint]=1
    [secrets]=1
    [workspaceFolder]=1
    [workspaceMount]=1
    [mounts]=1
    [runArgs]=1
    [containerEnv]=1
    [remoteEnv]=1
    [remoteUser]=1
    [containerUser]=1
    [updateRemoteUserUID]=1
    [containerName]=1
    [waitFor]=1
    [postCreateCommand]=1
    [postStartCommand]=1
    [postAttachCommand]=1
    [initializeCommand]=1
    [onCreateCommand]=1
    [updateContentCommand]=1
    [shutdownAction]=1
    [features]=1
    [overrideFeatureInstallOrder]=1
    [customizations]=1
    [forwardPorts]=1
    [portsAttributes]=1
    [otherPortsAttributes]=1
    [appPort]=1
    [hostRequirements]=1
    [capAdd]=1
    [securityOpt]=1
    [privileged]=1
    [init]=1
    [overrideCommand]=1
    [userEnvProbe]=1
    [runtime]=1
  )
  # Add the JSON Schema marker key separately: shfmt rewrites a
  # double-quoted key inside the array literal back to single quotes,
  # which then triggers shellcheck SC2016.
  # shellcheck disable=SC2016
  allowed_keys['$schema']=1

  while IFS= read -r key; do
    [[ -n $key ]] || continue
    if [[ -z ${allowed_keys[$key]:-} ]]; then
      printf 'Unsupported devcontainer.json key: %s (layer: %s)\n' "$key" "$layer_path" >&2
      return 1
    fi
  done < <(jq -r 'keys[]' <<<"$layer_json")

  runtime_value="$(jq -r '.runtime // empty' <<<"$layer_json")"
  if [[ -n $runtime_value && $runtime_value != "krun" ]]; then
    printf 'Unsupported devcontainer.json key: runtime=%s (layer: %s)\n' "$runtime_value" "$layer_path" >&2
    return 1
  fi
}
