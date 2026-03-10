#!/usr/bin/env bash

set -euo pipefail

install_systemd=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --systemd)
      install_systemd=true
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

printf 'Installing dctl to %s\n' "${BIN_DIR:-$HOME/.local/bin}"
make install

if [[ "$install_systemd" == true ]]; then
  make install-systemd
fi
