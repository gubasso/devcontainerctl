#!/usr/bin/env bash

set -euo pipefail

remove_systemd=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --systemd)
      remove_systemd=true
      shift
      ;;
    -h | --help)
      printf 'Usage: %s [--systemd]\n' "$0"
      exit 0
      ;;
    *)
      printf 'Usage: %s [--systemd]\n' "$0" >&2
      exit 1
      ;;
  esac
done

if [[ "$remove_systemd" == true ]]; then
  make uninstall-systemd
fi

printf 'Uninstalling dctl from %s\n' "${BIN_DIR:-$HOME/.local/bin}"
make uninstall
