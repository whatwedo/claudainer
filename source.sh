#!/usr/bin/env bash
# Usage: source source.sh
# Provides the claudainer command in your shell.

_CLAUDAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CLAUDAINER_BASE_URL="https://raw.githubusercontent.com/whatwedo/claudainer/refs/heads/main"

_claudainer_source() {
  local file="$1"
  if [ -f "$_CLAUDAINER_DIR/$file" ]; then
    source "$_CLAUDAINER_DIR/$file"
  else
    source <(curl -fsSL "$_CLAUDAINER_BASE_URL/$file")
  fi
}

case "$(uname -s)" in
  Darwin) _claudainer_source source.macos.sh ;;
  Linux)  _claudainer_source source.linux.sh ;;
  *)      echo "claudainer: unsupported OS: $(uname -s)" >&2 ;;
esac

unset -f _claudainer_source

claudainer() {
  local pull_flag=""
  local docker_flag=false
  local claude_args=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --pull)   pull_flag="--pull=always"; shift ;;
      --docker-socket|--ds) docker_flag=true; shift ;;
      --)       shift; claude_args+=("$@"); break ;;
      *)        claude_args+=("$1"); shift ;;
    esac
  done

  touch ~/.claude.json 2>/dev/null || true
  mkdir -p ~/.claude

  _claudainer_setup "$docker_flag"

  "$_CLAUDAINER_RUNTIME" run --rm -it $pull_flag \
    "${_CLAUDAINER_SOCKET_ARGS[@]}" \
    "${_CLAUDAINER_USER_ARGS[@]}" \
    -v ~/.claude:/home/developer/.claude \
    -v ~/.claude.json:/home/developer/.claude.json \
    -v "$(pwd)":/workspace \
    -e HOME=/home/developer \
    ghcr.io/whatwedo/claudainer:latest \
    claude "${claude_args[@]}"
}

unset _CLAUDAINER_DIR _CLAUDAINER_BASE_URL
