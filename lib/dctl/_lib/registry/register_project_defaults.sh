# shellcheck shell=bash

[[ -n ${_DCTL_REGISTRY_REGISTER_PROJECT_DEFAULTS_LOADED:-} ]] && return 0
readonly _DCTL_REGISTRY_REGISTER_PROJECT_DEFAULTS_LOADED=1

: "${DCTL_LIB_DIR:?DCTL_LIB_DIR must be set before sourcing _lib helpers}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/registry/file.sh
__dctl_require _lib/registry/exists.sh
__dctl_require _lib/registry/validate.sh
__dctl_require _lib/registry/has_project.sh
__dctl_require _lib/registry/ensure_file.sh

register_project_defaults() {
  local canonical_name="$1"
  local manifest_name="$2"
  local force="${3:-false}"

  require_cmd yq
  _registry_ensure_file

  local registry
  registry="$(_registry_file)"

  if [[ -s $registry ]]; then
    if [[ $force == true ]]; then
      if ! yq eval '.' "$registry" >/dev/null 2>&1; then
        err "Invalid YAML in $registry"
      fi
    else
      _validate_registry "$registry"
    fi
  fi

  local project_exists=false
  if _registry_has_project "$canonical_name"; then
    project_exists=true
    if [[ $force != true ]]; then
      warn "Project '$canonical_name' already registered in $registry; skipping"
      return 0
    fi
  fi

  # Use env vars to pass values safely to yq (avoids injection via special chars)
  local existing_sibling="true"
  if [[ $force == true && $project_exists == true ]]; then
    local has_sibling_key
    has_sibling_key="$(YQ_KEY="$canonical_name" yq -r '.[env(YQ_KEY)] | has("sibling_discovery")' "$registry" 2>/dev/null || true)"
    if [[ $has_sibling_key == "true" ]]; then
      existing_sibling="$(YQ_KEY="$canonical_name" yq -r '.[env(YQ_KEY)].sibling_discovery' "$registry" 2>/dev/null || printf 'true\n')"
    fi
  fi

  local yq_expr
  yq_expr='.[env(YQ_KEY)]["devcontainer-manifest"] = strenv(YQ_MANIFEST)'
  if [[ $existing_sibling == "false" ]]; then
    yq_expr+=' | .[env(YQ_KEY)].sibling_discovery = false'
  else
    yq_expr+=' | del(.[env(YQ_KEY)].sibling_discovery)'
  fi
  if [[ $force == true ]]; then
    # Migrate legacy keys registry-wide so a forced write is also a one-shot
    # migration path. For each entry that still has a legacy `devcontainer:`
    # path of the form `<...>/<manifest>/devcontainer.json` (the only shape
    # the prior contract emitted), derive `devcontainer-manifest` from
    # basename(dirname(path)) when the manifest field is not already set.
    # Then drop the legacy `devcontainer`, `dockerfile`, and `image`
    # keys. The `del(.dockerfile)` expression below is the migration
    # path that strips the deprecated `dockerfile` key from project
    # configs; do not rename it. This file is path-excluded from the
    # check-no-docker grep gate (see Makefile) precisely so this
    # legacy-migration code can stay plain-English.
    # Entries that have neither key are left untouched. Any derived manifest
    # name that does not match the schema pattern is caught by the post-write
    # _validate_registry call below.
    yq_expr+=' | with_entries(.value |= ('
    yq_expr+='(.["devcontainer-manifest"] = ('
    yq_expr+='(.["devcontainer-manifest"] // (.["devcontainer"] | sub("/devcontainer\.json$"; "") | sub("^.*/"; "")))'
    yq_expr+=')) | ('
    yq_expr+='select(.["devcontainer-manifest"] == null or .["devcontainer-manifest"] == "") '
    yq_expr+='| del(.["devcontainer-manifest"])'
    yq_expr+=') // . '
    yq_expr+='| del(.["devcontainer"]) | del(.dockerfile) | del(.image)'
    yq_expr+='))'
  fi

  local tmp_registry="${registry}.tmp.$$"
  export YQ_KEY="$canonical_name" YQ_MANIFEST="$manifest_name"
  if [[ -s $registry ]]; then
    yq eval "$yq_expr" "$registry" >"$tmp_registry"
  else
    yq -n "$yq_expr" >"$tmp_registry"
  fi
  unset YQ_KEY YQ_MANIFEST

  mv "$tmp_registry" "$registry"
  _validate_registry "$registry"

  log "Registered project '$canonical_name' (devcontainer-manifest: $manifest_name) in $registry"
}
