# shellcheck shell=bash
# Deploy command for dctl (sourced, not executed directly)

[[ -n ${_DCTL_DEPLOY_LOADED:-} ]] && return 0
readonly _DCTL_DEPLOY_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/config.sh"

usage_deploy() {
  cat <<'EOF'
Usage: dctl deploy [selector] [options]

Selectors:
  devcontainer <name>             Deploy one devcontainer template
  image <name>                    Deploy one image
  --all                           Deploy all devcontainers and images
  --all-devcontainers             Deploy all devcontainers
  --all-images                    Deploy all images

Options:
  --reset                         Back up and overwrite shipped files
  --dry-run                       Print the per-file plan and change nothing
  --list                          List deployment state for both categories
  --list-devcontainers            List devcontainer deployment state
  --list-images                   List image deployment state
  --help, -h                      Show this help text

Interactive:
  dctl deploy                     Pick a category, pick item(s), confirm, deploy
EOF
}

_discover_installed_devcontainers() {
  local manifests=()
  shopt -s nullglob
  local f name
  for f in "$DEVCONTAINERS_DIR"/*.yaml; do
    name="$(basename "$f" .yaml)"
    manifests+=("$name")
  done
  shopt -u nullglob
  [[ ${#manifests[@]} -gt 0 ]] && printf '%s\n' "${manifests[@]}"
}

_discover_deployed_devcontainers() {
  local manifests=()
  shopt -s nullglob
  local f name
  for f in "$DCTL_DEVCONTAINER_DIR"/*.yaml; do
    name="$(basename "$f" .yaml)"
    manifests+=("$name")
  done
  shopt -u nullglob
  [[ ${#manifests[@]} -gt 0 ]] && printf '%s\n' "${manifests[@]}"
}

_discover_installed_images() {
  local targets=()
  shopt -s nullglob
  local dir name
  for dir in "$IMAGES_DIR"/*/; do
    [[ -f "${dir}Dockerfile" ]] || continue
    name="$(basename "$dir")"
    targets+=("$name")
  done
  shopt -u nullglob
  [[ ${#targets[@]} -gt 0 ]] && printf '%s\n' "${targets[@]}"
}

_discover_deployed_images() {
  local targets=()
  shopt -s nullglob
  local dir name
  for dir in "$DCTL_IMAGES_DIR"/*/; do
    [[ -f "${dir}Dockerfile" ]] || continue
    name="$(basename "$dir")"
    targets+=("$name")
  done
  shopt -u nullglob
  [[ ${#targets[@]} -gt 0 ]] && printf '%s\n' "${targets[@]}"
}

_discover_installed_selectable_devcontainers() {
  _discover_installed_devcontainers
}

_discover_deployed_selectable_devcontainers() {
  _discover_deployed_devcontainers
}

_category_installed_root() {
  case "$1" in
    devcontainer) printf '%s\n' "$DEVCONTAINERS_DIR" ;;
    image) printf '%s\n' "$IMAGES_DIR" ;;
    *) err "Unknown deploy category: $1" ;;
  esac
}

_category_deployed_root() {
  case "$1" in
    devcontainer) printf '%s\n' "$DCTL_DEVCONTAINER_DIR" ;;
    image) printf '%s\n' "$DCTL_IMAGES_DIR" ;;
    *) err "Unknown deploy category: $1" ;;
  esac
}

_preview_file_for_category() {
  case "$1" in
    devcontainer) printf 'devcontainer.json\n' ;;
    image) printf 'Dockerfile\n' ;;
    *) err "Unknown deploy category: $1" ;;
  esac
}

_print_status_group() {
  local title="$1"
  shift
  local -a items=("$@")

  printf '%s\n' "$title"
  if [[ ${#items[@]} -eq 0 ]]; then
    printf '  (none found)\n'
    return
  fi
  printf '  %s\n' "${items[@]}"
}

_collect_dir_plan_entries() {
  local category="$1"
  local name="$2"
  local mode="$3"
  local internal="${4:-false}"

  local src_root dest_root src_dir dest_dir
  src_root="$(_category_installed_root "$category")"
  dest_root="$(_category_deployed_root "$category")"
  src_dir="${src_root}/${name}"
  dest_dir="${dest_root}/${name}"

  [[ -d $src_dir ]] || return 0

  local source rel dest action
  while IFS= read -r source; do
    [[ -n $source ]] || continue
    rel="${source#"${src_dir}"/}"
    dest="${dest_dir}/${rel}"

    if [[ ! -f $dest ]]; then
      action="CREATE"
    elif cmp -s "$source" "$dest"; then
      action="NOOP-IDENTICAL"
    elif [[ $mode == "reset" ]]; then
      action="OVERWRITE-WITH-BACKUP"
    elif [[ $category == "devcontainer" && $internal == true ]]; then
      action="OVERWRITE"
    else
      action="SKIP-EXISTS"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$action" "$category" "$name" "$internal" "$source" "$dest"
  done < <(find "$src_dir" -type f | sort)
}

_collect_deploy_plan() {
  local category="$1"
  local name="$2"
  local mode="$3"

  case "$category" in
    devcontainer)
      local manifest
      manifest="$(installed_compose_manifest_path "$name")"
      [[ -f $manifest ]] || return 0
      _validate_compose_manifest "$manifest"

      local -a layers=()
      mapfile -t layers < <(_read_manifest_layers "$manifest")
      local layer_count="${#layers[@]}"
      local i=0
      local layer_name is_leaf src_layer_dir
      for layer_name in "${layers[@]}"; do
        src_layer_dir="${DEVCONTAINERS_DIR}/${layer_name}"
        [[ -d $src_layer_dir ]] || err "Manifest '${name}' references layer '${layer_name}' but installed directory not found: ${src_layer_dir}"
        [[ -f "${src_layer_dir}/devcontainer.json" ]] || err "Manifest '${name}' references layer '${layer_name}' but devcontainer.json not found in: ${src_layer_dir}"
        i=$((i + 1))
        if [[ $i -eq $layer_count ]]; then
          is_leaf=true
        else
          is_leaf=false
        fi
        _collect_dir_plan_entries "$category" "$layer_name" "$mode" "$([[ $is_leaf == false ]] && printf true || printf false)"
      done

      local src_manifest dest_manifest action
      src_manifest="$(installed_compose_manifest_path "$name")"
      dest_manifest="$(config_compose_manifest_path "$name")"
      if [[ -f $src_manifest ]]; then
        if [[ ! -f $dest_manifest ]]; then
          action="CREATE"
        elif cmp -s "$src_manifest" "$dest_manifest"; then
          action="NOOP-IDENTICAL"
        elif [[ $mode == "reset" ]]; then
          action="OVERWRITE-WITH-BACKUP"
        else
          action="OVERWRITE"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$action" "$category" "$name" "true" "$src_manifest" "$dest_manifest"
      fi
      ;;
    image)
      _collect_dir_plan_entries "$category" "$name" "$mode" false
      ;;
    *)
      err "Unknown deploy category: $category"
      ;;
  esac
}

_dedupe_plan() {
  local plan="$1"
  local line dest
  local -A seen=()
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    dest="$(printf '%s\n' "$line" | awk -F '\t' '{print $6}')"
    [[ -n $dest ]] || continue
    [[ -n ${seen[$dest]:-} ]] && continue
    seen["$dest"]=1
    printf '%s\n' "$line"
  done <<<"$plan"
}

_backup_target_file() {
  local path="$1"
  local timestamp backup_path
  timestamp="$(date -u '+%Y-%m-%dT%H-%M-%SZ')"
  backup_path="${path}.bak.${timestamp}"
  mv "$path" "$backup_path"
  printf '%s\n' "$backup_path"
}

_install_mode_for_source() {
  if [[ -x $1 ]]; then
    printf '755\n'
  else
    printf '644\n'
  fi
}

_print_deploy_plan() {
  local plan="$1"
  local line action category name source dest
  while IFS=$'\t' read -r action category name _internal source dest; do
    [[ -n $action ]] || continue
    printf '%-22s %-12s %-18s %s -> %s\n' \
      "$action" "$category" "$name" "$source" "$dest"
  done <<<"$plan"
}

_apply_deploy_plan() {
  local plan="$1"
  local line action category name source dest backup_path mode

  while IFS=$'\t' read -r action category name _internal source dest; do
    [[ -n $action ]] || continue
    case "$action" in
      CREATE)
        mkdir -p "$(dirname "$dest")"
        mode="$(_install_mode_for_source "$source")"
        install -m "$mode" "$source" "$dest"
        log "created ${category} '${name}': ${dest}"
        ;;
      OVERWRITE)
        mkdir -p "$(dirname "$dest")"
        mode="$(_install_mode_for_source "$source")"
        install -m "$mode" "$source" "$dest"
        log "reconciled managed ${category} '${name}': ${dest}"
        ;;
      OVERWRITE-WITH-BACKUP)
        backup_path="$(_backup_target_file "$dest")"
        mode="$(_install_mode_for_source "$source")"
        install -m "$mode" "$source" "$dest"
        log "backed up ${dest} to ${backup_path}"
        log "overwrote ${category} '${name}': ${dest}"
        ;;
      SKIP-EXISTS)
        log "skipped ${category} '${name}': ${dest} (exists; pass --reset to overwrite)"
        ;;
      NOOP-IDENTICAL)
        log "unchanged ${category} '${name}': ${dest}"
        ;;
      *)
        err "Unknown deploy action: $action"
        ;;
    esac
  done <<<"$plan"
}

list_deploy_entries() {
  local scope="${1:-both}"
  local -A installed=()
  local -A deployed=()
  local -a lines=()
  local name status

  case "$scope" in
    devcontainer | both)
      installed=()
      deployed=()
      while IFS= read -r name; do
        [[ -n $name ]] || continue
        installed["$name"]=1
      done < <(_discover_installed_selectable_devcontainers)
      while IFS= read -r name; do
        [[ -n $name ]] || continue
        deployed["$name"]=1
      done < <(_discover_deployed_selectable_devcontainers)
      lines=()
      for name in "${!installed[@]}" "${!deployed[@]}"; do
        [[ -n $name ]] || continue
        if [[ -n ${installed[$name]:-} && -n ${deployed[$name]:-} ]]; then
          status="deployed"
        elif [[ -n ${installed[$name]:-} ]]; then
          status="installed"
        else
          status="user-only"
        fi
        lines+=("${status}  ${name}")
      done
      mapfile -t lines < <(printf '%s\n' "${lines[@]}" | awk 'NF' | sort -u)
      _print_status_group "Devcontainers:" "${lines[@]}"
      ;;
  esac

  case "$scope" in
    image | both)
      installed=()
      deployed=()
      while IFS= read -r name; do
        [[ -n $name ]] || continue
        installed["$name"]=1
      done < <(_discover_installed_images)
      while IFS= read -r name; do
        [[ -n $name ]] || continue
        deployed["$name"]=1
      done < <(_discover_deployed_images)
      lines=()
      for name in "${!installed[@]}" "${!deployed[@]}"; do
        [[ -n $name ]] || continue
        if [[ -n ${installed[$name]:-} && -n ${deployed[$name]:-} ]]; then
          status="deployed"
        elif [[ -n ${installed[$name]:-} ]]; then
          status="installed"
        else
          status="user-only"
        fi
        lines+=("${status}  ${name}")
      done
      mapfile -t lines < <(printf '%s\n' "${lines[@]}" | awk 'NF' | sort -u)
      _print_status_group "Images:" "${lines[@]}"
      ;;
  esac
}

_select_deploy_category_interactive() {
  command -v fzf >/dev/null 2>&1 || err "fzf not found. Install fzf or use an explicit deploy selector."
  [[ -t 0 ]] || err "Interactive deploy requires a terminal. Use an explicit deploy selector."

  printf 'devcontainer\nimage\n' | _fzf_pick \
    "Select deploy category: " \
    "ENTER: confirm, ESC: cancel"
}

_select_deploy_targets_interactive() {
  local category="$1"
  local -a available=()
  local preview_file preview_cmd root

  command -v fzf >/dev/null 2>&1 || err "fzf not found. Install fzf or use an explicit deploy selector."
  [[ -t 0 ]] || err "Interactive deploy requires a terminal. Use an explicit deploy selector."

  case "$category" in
    devcontainer)
      mapfile -t available < <(_discover_installed_selectable_devcontainers)
      ;;
    image)
      mapfile -t available < <(_discover_installed_images)
      ;;
    *)
      err "Unknown deploy category: $category"
      ;;
  esac

  [[ ${#available[@]} -gt 0 ]] || err "No installed ${category} entries found"

  preview_file="$(_preview_file_for_category "$category")"
  root="$(_category_installed_root "$category")"
  case "$category" in
    devcontainer)
      preview_cmd="bash -lc 'file=\"${root}/{}.yaml\"; [[ -f \"\$file\" ]] && sed -n \"1,200p\" \"\$file\"'"
      ;;
    image)
      preview_cmd="bash -lc 'file=\"${root}/{}/${preview_file}\"; [[ -f \"\$file\" ]] && sed -n \"1,200p\" \"\$file\"'"
      ;;
    *)
      err "Unknown deploy category: $category"
      ;;
  esac

  printf '%s\n' "${available[@]}" | fzf --multi \
    --height=~50% \
    --layout=reverse \
    --border \
    --prompt="Select ${category} entries: " \
    --header="TAB: multi-select, ENTER: confirm, ESC: cancel" \
    --preview "$preview_cmd" \
    --preview-window "right:60%:wrap"
}

_confirm_deploy_plan_interactive() {
  local plan="$1"
  local reply

  printf 'Planned actions:\n'
  _print_deploy_plan "$plan"
  printf 'Apply this plan? [y/N] ' >/dev/tty
  read -r reply </dev/tty || return 1
  [[ $reply == "y" || $reply == "Y" ]]
}

_installed_entry_exists() {
  local category="$1"
  local name="$2"
  case "$category" in
    devcontainer)
      [[ -f "${DEVCONTAINERS_DIR}/${name}.yaml" ]]
      ;;
    image)
      local root preview
      root="$(_category_installed_root "$category")"
      preview="$(_preview_file_for_category "$category")"
      [[ -f "${root}/${name}/${preview}" ]]
      ;;
    *)
      err "Unknown deploy category: $category"
      ;;
  esac
}

cmd_deploy() {
  local reset=false
  local dry_run=false
  local list_scope=""
  local all=false
  local all_devcontainers=false
  local all_images=false
  local -a positional=()
  local selection_count=0
  local category="" name=""
  local -a names=()
  local plan="" deduped_plan=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reset)
        reset=true
        shift
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --list)
        list_scope="both"
        shift
        ;;
      --list-devcontainers)
        list_scope="devcontainer"
        shift
        ;;
      --list-images)
        list_scope="image"
        shift
        ;;
      --all)
        all=true
        shift
        ;;
      --all-devcontainers)
        all_devcontainers=true
        shift
        ;;
      --all-images)
        all_images=true
        shift
        ;;
      --help | -h)
        usage_deploy
        return 0
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [[ $dry_run == true && $reset == true ]]; then
    err "Cannot use --dry-run with --reset"
  fi

  [[ -n $list_scope ]] && selection_count=$((selection_count + 1))
  [[ $all == true ]] && selection_count=$((selection_count + 1))
  [[ $all_devcontainers == true ]] && selection_count=$((selection_count + 1))
  [[ $all_images == true ]] && selection_count=$((selection_count + 1))
  [[ ${#positional[@]} -gt 0 ]] && selection_count=$((selection_count + 1))

  [[ $selection_count -le 1 ]] || err "Choose exactly one deploy selector or list mode"

  if [[ -n $list_scope ]]; then
    list_deploy_entries "$list_scope"
    return 0
  fi

  if [[ ${#positional[@]} -gt 0 ]]; then
    [[ ${#positional[@]} -eq 2 ]] || err "Usage: dctl deploy <devcontainer|image> <name> [--reset|--dry-run]"
    category="${positional[0]}"
    name="${positional[1]}"
    case "$category" in
      devcontainer | image) ;;
      *) err "Unknown deploy selector: $category" ;;
    esac
  elif [[ $all != true && $all_devcontainers != true && $all_images != true ]]; then
    category="$(_select_deploy_category_interactive)" || return $?
    mapfile -t names < <(_select_deploy_targets_interactive "$category")
    [[ ${#names[@]} -gt 0 ]] || return 0
  fi

  if [[ -n $name ]]; then
    _installed_entry_exists "$category" "$name" || err "Unknown installed ${category}: $name"
    names=("$name")
  elif [[ $all_devcontainers == true ]]; then
    category="devcontainer"
    mapfile -t names < <(_discover_installed_devcontainers)
  elif [[ $all_images == true ]]; then
    category="image"
    mapfile -t names < <(_discover_installed_images)
  fi

  if [[ $all == true ]]; then
    local dev_name image_name plan_output
    while IFS= read -r dev_name; do
      [[ -n $dev_name ]] || continue
      plan_output="$(_collect_deploy_plan devcontainer "$dev_name" "$([[ $reset == true ]] && printf reset || printf normal)")" || exit $?
      plan+="$plan_output"$'\n'
    done < <(_discover_installed_devcontainers)
    while IFS= read -r image_name; do
      [[ -n $image_name ]] || continue
      plan_output="$(_collect_deploy_plan image "$image_name" "$([[ $reset == true ]] && printf reset || printf normal)")" || exit $?
      plan+="$plan_output"$'\n'
    done < <(_discover_installed_images)
  else
    for name in "${names[@]}"; do
      local plan_output
      plan_output="$(_collect_deploy_plan "$category" "$name" "$([[ $reset == true ]] && printf reset || printf normal)")" || exit $?
      plan+="$plan_output"$'\n'
    done
  fi

  deduped_plan="$(_dedupe_plan "$plan")"
  [[ -n $deduped_plan ]] || err "No deploy actions available"

  if [[ ${#positional[@]} -eq 0 && $all != true && $all_devcontainers != true && $all_images != true ]]; then
    _confirm_deploy_plan_interactive "$deduped_plan" || return 0
  fi

  if [[ $dry_run == true ]]; then
    _print_deploy_plan "$deduped_plan"
    return 0
  fi

  _apply_deploy_plan "$deduped_plan"
}

main_deploy() {
  cmd_deploy "$@"
}
