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

_claudainer_proxy_setup() {
  local network="claudainer-net"
  local container="claudainer-proxy"
  local proxy_image="ghcr.io/whatwedo/claudainer-proxy:latest"

  "$_CLAUDAINER_RUNTIME" network inspect "$network" >/dev/null 2>&1 \
    || "$_CLAUDAINER_RUNTIME" network create "$network"

  if ! "$_CLAUDAINER_RUNTIME" inspect "$container" >/dev/null 2>&1; then
    "$_CLAUDAINER_RUNTIME" run -d --rm --name "$container" \
      --network "$network" \
      "$proxy_image"
  fi

  _CLAUDAINER_NETWORK_ARGS=(--network "$network")
  _CLAUDAINER_PROXY_ARGS=(
    -e HTTP_PROXY=http://${container}:3128
    -e HTTPS_PROXY=http://${container}:3128
    -e NO_PROXY=localhost,127.0.0.1
  )
}

claudainer-proxy-stop() {
  local network="claudainer-net"
  local container="claudainer-proxy"
  local runtime
  if command -v podman >/dev/null 2>&1; then
    runtime=podman
  elif command -v docker >/dev/null 2>&1; then
    runtime=docker
  else
    echo "claudainer-proxy-stop: neither podman nor docker found in PATH" >&2
    return 1
  fi

  "$runtime" stop "$container" 2>/dev/null && "$runtime" rm "$container" 2>/dev/null || true
  "$runtime" network rm "$network" 2>/dev/null || true
}

# Populate _CLAUDAINER_ENV_MASK_ARGS with read-only /dev/null masks for every
# .env-style secret file under the current directory, so they read as empty
# inside /workspace. Template files and heavy dependency dirs are skipped.
_claudainer_env_masks() {
  _CLAUDAINER_ENV_MASK_ARGS=()
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#./}"
    case "$rel" in
      *.example|*.sample|*.dist|*.template) continue ;;
    esac
    _CLAUDAINER_ENV_MASK_ARGS+=(-v "/dev/null:/workspace/$rel:ro")
  done < <(find . \
    \( -name .git -o -name node_modules -o -name vendor \) -prune -o \
    -type f \( -name '.env' -o -name '.env.*' \) -print0)
}

claudainer() {
  local pull_flag=""
  local docker_flag=false
  local shell_flag=false
  local git_config_flag=false
  local include_env_flag=false
  local claude_args=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --pull)   pull_flag="--pull=always"; shift ;;
      --docker-socket|--ds) docker_flag=true; shift ;;
      --shell)  shell_flag=true; shift ;;
      --git-config|--gc) git_config_flag=true; shift ;;
      --include-env) include_env_flag=true; shift ;;
      --)       shift; claude_args+=("$@"); break ;;
      *)        claude_args+=("$1"); shift ;;
    esac
  done

  touch ~/.claude.json 2>/dev/null || true
  mkdir -p ~/.claude

  _claudainer_setup "$docker_flag" || return 1
  _claudainer_proxy_setup || return 1

  local _CLAUDAINER_CMD=()
  if [ "$shell_flag" = true ]; then
    _CLAUDAINER_CMD=(bash)
  else
    _CLAUDAINER_CMD=(claude "${claude_args[@]}")
  fi

  # Mirror ~/.claude at the host's absolute home path inside the container too,
  # so absolute paths baked into the config (e.g. hook commands) resolve.
  local host_home_args=()
  if [ -n "$HOME" ] && [ "$HOME" != "/home/developer" ]; then
    host_home_args=(
      -v ~/.claude:"$HOME/.claude"
      -v ~/.claude.json:"$HOME/.claude.json"
    )
  fi

  local git_config_args=()
  if [ "$git_config_flag" = true ]; then
    [ -f ~/.gitconfig ] && git_config_args+=(-v ~/.gitconfig:/home/developer/.gitconfig:ro)
    [ -d ~/.config/git ] && git_config_args+=(-v ~/.config/git:/home/developer/.config/git:ro)
  fi

  local _CLAUDAINER_ENV_MASK_ARGS=()
  if [ "$include_env_flag" != true ]; then
    _claudainer_env_masks
    if [ "${#_CLAUDAINER_ENV_MASK_ARGS[@]}" -gt 0 ]; then
      echo "claudainer: excluding $(( ${#_CLAUDAINER_ENV_MASK_ARGS[@]} / 2 )) .env file(s) from /workspace (pass --include-env to mount them)" >&2
    fi
  fi

  "$_CLAUDAINER_RUNTIME" run --rm -it $pull_flag \
    "${_CLAUDAINER_SOCKET_ARGS[@]}" \
    "${_CLAUDAINER_USER_ARGS[@]}" \
    "${_CLAUDAINER_NETWORK_ARGS[@]}" \
    "${_CLAUDAINER_PROXY_ARGS[@]}" \
    -v ~/.claude:/home/developer/.claude \
    -v ~/.claude.json:/home/developer/.claude.json \
    "${host_home_args[@]}" \
    "${git_config_args[@]}" \
    -v "$(pwd)":/workspace \
    "${_CLAUDAINER_ENV_MASK_ARGS[@]}" \
    -e HOME=/home/developer \
    -e TERM="${TERM:-xterm-256color}" \
    ghcr.io/whatwedo/claudainer:latest \
    "${_CLAUDAINER_CMD[@]}"
}

unset _CLAUDAINER_DIR _CLAUDAINER_BASE_URL
