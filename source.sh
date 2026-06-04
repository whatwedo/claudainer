#!/usr/bin/env bash
# Usage: source source.sh
# Provides the claudainer command in your shell.

_CLAUDAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
  Darwin)
    # shellcheck source=source.macos.sh
    source "$_CLAUDAINER_DIR/source.macos.sh"
    ;;
  Linux)
    # shellcheck source=source.linux.sh
    source "$_CLAUDAINER_DIR/source.linux.sh"
    ;;
  *)
    echo "claudainer: unsupported OS: $(uname -s)" >&2
    ;;
esac

unset _CLAUDAINER_DIR
