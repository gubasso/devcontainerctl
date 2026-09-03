# shellcheck shell=bash
# Host-provider integration for dctl (sourced, not executed directly)
#
# A provider is a host executable declared in a compose manifest's `providers`
# list. dctl invokes it around the workspace lifecycle — prepare before up,
# attach before exec, release on down, check from dctl test — and composes its
# JSON answer ({"mounts": [...], "remoteEnv": {...}}) into the devcontainer CLI
# invocation. dctl composes the argv itself; a provider never emits raw flags.
#
# dctl stays agnostic about what a provider manages: the contract is
# docs/specs/host-providers/SPEC.md, and the provider implementations live with
# the host configuration that owns them (nix-secrets' dctl-nix-store is the
# first), the same split the forge-seed contract in auth.sh already runs.

[[ -n ${_DCTL_PROVIDERS_LOADED:-} ]] && return 0
readonly _DCTL_PROVIDERS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

# Print the current project's compose manifest path, or nothing.
# Providers are declared per manifest, so an explicit config (--config flag or
# DCTL_CONFIG) bypasses them together with the manifest it bypasses.
current_project_manifest_path() {
  [[ -z ${DCTL_CLI_CONFIG:-} ]] || return 0
  [[ ! -v DCTL_CONFIG ]] || return 0

  local canonical_name manifest_name manifest
  canonical_name="$(resolve_canonical_project_name)"
  manifest_name="$(_registry_lookup_devcontainer_manifest "$canonical_name")"
  [[ -n $manifest_name ]] || return 0

  manifest="$(config_compose_manifest_path "$manifest_name")"
  [[ -f $manifest ]] || return 0

  printf '%s\n' "$manifest"
}

_read_manifest_providers() {
  local manifest="$1"
  yq eval -o=json '.providers // []' "$manifest" \
    | jq -r '.[] | "\(.name)\t\(if has("required") then .required else true end)"'
}

# Print "name<TAB>required" rows for the current project, in manifest order.
# Empty output when no manifest governs this workspace or none declares
# providers — the feature costs nothing where it is not used.
list_project_providers() {
  local manifest
  manifest="$(current_project_manifest_path)"
  [[ -n $manifest ]] || return 0

  require_cmd yq
  require_cmd jq
  _read_manifest_providers "$manifest"
}

# Run one provider phase. The provider's stdout (its JSON answer) is this
# function's stdout; its stderr passes through to the user.
provider_invoke() {
  local name="$1"
  local phase="$2"
  "$name" "$phase" --workspace "$WORKSPACE_FOLDER" --project "$(resolve_canonical_project_name)"
}

# Validate a provider's JSON answer and append the devcontainer CLI args it
# implies. Empty output is a valid "nothing to add". Returns 1 on a malformed
# answer; the caller decides whether that aborts (required) or warns (optional).
_provider_json_to_args() {
  local name="$1"
  local json="$2"
  # shellcheck disable=SC2178
  local -n _json_out="$3"

  [[ -n $json ]] || return 0

  # Strict shape check, without jq's `//` fallback: `//` treats false and null
  # as absent, so `{"mounts": false}` would read as an empty answer and a
  # required provider's broken output would silently start the container
  # without its mounts. Unknown top-level keys are rejected too — the spec says
  # extend the contract before extending the shape.
  if ! jq -e '
    type == "object"
    and (keys - ["mounts", "remoteEnv"] == [])
    and ((has("mounts") | not) or (.mounts | type == "array" and all(.[]; type == "string")))
    and ((has("remoteEnv") | not) or (.remoteEnv | type == "object" and ([.[]] | all(type == "string"))))
  ' <<<"$json" >/dev/null 2>&1; then
    warn "Provider '$name' returned a malformed answer (expected {\"mounts\": [string...], \"remoteEnv\": {string: string}} and no other keys)"
    return 1
  fi

  local entry
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    _json_out+=(--mount "$entry")
  done < <(jq -r '(.mounts // [])[]' <<<"$json")

  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    _json_out+=(--remote-env "$entry")
  done < <(jq -r '(.remoteEnv // {}) | to_entries[] | "\(.key)=\(.value)"' <<<"$json")
}

# Usage: local -a provider_args=(); collect_provider_args <phase> provider_args
# Aborts (err) when a required provider is missing, fails, or answers
# malformed JSON; an optional provider degrades to a warning, the forge-seed
# warn-don't-fail policy.
collect_provider_args() {
  local phase="$1"
  # shellcheck disable=SC2178
  local -n _args_out="$2"
  # shellcheck disable=SC2034
  _args_out=()

  local -a rows=()
  mapfile -t rows < <(list_project_providers)
  [[ ${#rows[@]} -gt 0 ]] || return 0

  local row name required output
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r name required <<<"$row"
    [[ -n $name ]] || continue

    if ! command -v "$name" >/dev/null 2>&1; then
      if [[ $required == "true" ]]; then
        err "Required provider '$name' not found on PATH (declared in the compose manifest)"
      fi
      warn "Optional provider '$name' not found — skipping"
      continue
    fi

    if ! output="$(provider_invoke "$name" "$phase")"; then
      if [[ $required == "true" ]]; then
        err "Required provider '$name' failed during '$phase'"
      fi
      warn "Optional provider '$name' failed during '$phase' — skipping"
      continue
    fi

    if ! _provider_json_to_args "$name" "$output" _args_out; then
      if [[ $required == "true" ]]; then
        err "Required provider '$name' answered '$phase' with malformed JSON"
      fi
      warn "Optional provider '$name' answered '$phase' with malformed JSON — skipping"
      continue
    fi
  done
}

# Single-invocation, capturable form of collect_provider_args: prints the
# composed args NUL-separated on stdout. Invoked inside a command
# substitution, a required-provider err terminates only the subshell, so a
# caller that must keep running after the failure (dctl test's smoke path)
# gets a nonzero status and every provider still ran exactly once.
collect_provider_args_nul() {
  local phase="$1"
  local -a _nul_args=()
  collect_provider_args "$phase" _nul_args
  if [[ ${#_nul_args[@]} -gt 0 ]]; then
    printf '%s\0' "${_nul_args[@]}"
  fi
}

# Invoke every declared provider's release phase, warn-only: down must not
# fail on a provider, and a provider with nothing to release answers cheaply.
provider_release_all() {
  local -a rows=()
  mapfile -t rows < <(list_project_providers)
  [[ ${#rows[@]} -gt 0 ]] || return 0

  local row name required
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r name required <<<"$row"
    [[ -n $name ]] || continue

    if ! command -v "$name" >/dev/null 2>&1; then
      continue
    fi

    if ! provider_invoke "$name" release >/dev/null; then
      warn "Provider '$name' failed during 'release'"
    fi
  done
}
