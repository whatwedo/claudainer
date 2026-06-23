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

_claudainer_source source.helpers.sh

unset -f _claudainer_source

_claudainer_proxy_setup() {
  local pull="${1:-false}"
  local network="claudainer-net"
  local container="claudainer-proxy"
  local proxy_image="ghcr.io/whatwedo/claudainer-proxy:latest"

  "$_CLAUDAINER_RUNTIME" network inspect "$network" >/dev/null 2>&1 \
    || "$_CLAUDAINER_RUNTIME" network create "$network"

  # With --pull, fetch the latest proxy image and force a restart below so a
  # currently-running proxy actually adopts the new image (it would otherwise be
  # left untouched as "healthy").
  [ "$pull" = true ] && "$_CLAUDAINER_RUNTIME" pull "$proxy_image"

  # Check whether the proxy is actually running, not just whether a container
  # record exists: a --rm container left behind by a host reboot/sleep lingers
  # in "exited" state, which a plain `inspect` would treat as healthy. Clear any
  # such stale container before (re)starting so the proxy comes back up.
  local running
  running="$("$_CLAUDAINER_RUNTIME" inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)"
  if [ "$pull" = true ] || [ "$running" != "true" ]; then
    "$_CLAUDAINER_RUNTIME" rm -f "$container" >/dev/null 2>&1 || true
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

# Paths excluded from /workspace when a project has no .claudainer yet. Written
# into a freshly created .claudainer and used as an in-memory fallback if the
# file cannot be created.
_CLAUDAINER_DEFAULT_EXCLUDES=(.env .env.local)

# Populate _CLAUDAINER_EXCLUDE_PATHS with newline-separated relative paths from
# the project's .claudainer exclude_paths list. The entrypoint applies the masks
# inside the container (bind /dev/null for files, tmpfs for directories) so that
# no host-side mounts are needed — which prevents Docker Desktop (VirtioFS) from
# creating stub files in the project directory. Creates .claudainer with defaults
# if it does not exist.
_claudainer_config_masks() {
  _CLAUDAINER_EXCLUDE_PATHS=""

  if [ ! -e .claudainer ]; then
    { printf 'exclude_paths:\n'; printf '  - %s\n' "${_CLAUDAINER_DEFAULT_EXCLUDES[@]}"; } > .claudainer 2>/dev/null \
      && echo "claudainer: created .claudainer with default exclude_paths (.env, .env.local)" >&2
  fi

  local val rel
  local paths=()
  if [ -f .claudainer ] && [ -r .claudainer ]; then
    while IFS= read -r val; do
      paths+=("$val")
    done < <(_claudainer_yaml_list .claudainer exclude_paths)
  else
    paths=("${_CLAUDAINER_DEFAULT_EXCLUDES[@]}")
  fi

  for val in "${paths[@]}"; do
    rel="${val#./}"; rel="${rel#/}"
    case "$rel" in
      ''|..|../*|*/../*|*/..)
        echo "claudainer: ignoring unsafe exclude_path '$val'" >&2; continue ;;
    esac
    [ -e "$rel" ] && _CLAUDAINER_EXCLUDE_PATHS="${_CLAUDAINER_EXCLUDE_PATHS}${rel}"$'\n'
  done
}

claudainer() {
  local pull_flag=false
  local docker_flag=false
  local shell_flag=false
  local git_config_flag=false
  local claude_args=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --pull)   pull_flag=true; shift ;;
      --enable-docker) docker_flag=true; shift ;;
      --shell)  shell_flag=true; shift ;;
      --enable-git) git_config_flag=true; shift ;;
      --)       shift; claude_args+=("$@"); break ;;
      *)        claude_args+=("$1"); shift ;;
    esac
  done

  touch ~/.claude.json 2>/dev/null || true
  mkdir -p ~/.claude

  _claudainer_setup "$docker_flag" || return 1
  _claudainer_proxy_setup "$pull_flag" || return 1

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

  local _CLAUDAINER_EXCLUDE_PATHS=""
  _claudainer_config_masks
  local _mask_count=0
  [ -n "$_CLAUDAINER_EXCLUDE_PATHS" ] && \
    _mask_count=$(printf '%s' "$_CLAUDAINER_EXCLUDE_PATHS" | wc -l | tr -d ' ')
  if [ "$_mask_count" -gt 0 ]; then
    echo "claudainer: excluding $_mask_count path(s) listed in .claudainer from /workspace" >&2
  fi

  local _exclude_args=()
  [ -n "$_CLAUDAINER_EXCLUDE_PATHS" ] && \
    _exclude_args=(-e "CLAUDAINER_EXCLUDE_PATHS=${_CLAUDAINER_EXCLUDE_PATHS}")

  local pull_arg=""
  [ "$pull_flag" = true ] && pull_arg="--pull=always"

  "$_CLAUDAINER_RUNTIME" run --rm -it $pull_arg \
    "${_CLAUDAINER_SOCKET_ARGS[@]}" \
    "${_CLAUDAINER_USER_ARGS[@]}" \
    "${_CLAUDAINER_NETWORK_ARGS[@]}" \
    "${_CLAUDAINER_PROXY_ARGS[@]}" \
    -v ~/.claude:/home/developer/.claude \
    -v ~/.claude.json:/home/developer/.claude.json \
    "${host_home_args[@]}" \
    "${git_config_args[@]}" \
    -v "$(pwd)":/workspace \
    "${_exclude_args[@]}" \
    -e HOME=/home/developer \
    -e TERM="${TERM:-xterm-256color}" \
    "${CLAUDAINER_IMAGE:-ghcr.io/whatwedo/claudainer:latest}" \
    "${_CLAUDAINER_CMD[@]}"
}

unset _CLAUDAINER_DIR _CLAUDAINER_BASE_URL
