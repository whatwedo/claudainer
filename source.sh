#!/usr/bin/env bash
# Usage: source source.sh  (from your local clone — see "Setup" in README.md)
# Provides the claudainer command in your shell.

# Locate this file so the platform and helper files are loaded from the clone
# next to it, and only from there: fetching them over the network would execute
# whatever the endpoint happens to serve in the user's shell.
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  _CLAUDAINER_SELF="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _CLAUDAINER_SELF="${(%):-%x}"   # zsh's equivalent of BASH_SOURCE[0]
else
  echo "claudainer: unsupported shell — source source.sh from bash or zsh" >&2
  return 1
fi
_CLAUDAINER_DIR="$(cd "$(dirname "$_CLAUDAINER_SELF")" && pwd)"

_claudainer_source() {
  local file="$1"
  if [ ! -f "$_CLAUDAINER_DIR/$file" ]; then
    echo "claudainer: $_CLAUDAINER_DIR/$file not found — source source.sh from a complete clone of the repository" >&2
    return 1
  fi
  source "$_CLAUDAINER_DIR/$file"
}

case "$(uname -s)" in
  Darwin) _claudainer_source source.macos.sh || return 1 ;;
  Linux)  _claudainer_source source.linux.sh || return 1 ;;
  *)      echo "claudainer: unsupported OS: $(uname -s)" >&2; return 1 ;;
esac

_claudainer_source source.helpers.sh || return 1

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

# Paths excluded from the project directory when a project has no .claudainer
# yet. Written into a freshly created .claudainer and used as an in-memory
# fallback if the file cannot be created.
_CLAUDAINER_DEFAULT_EXCLUDES=(.env .env.local)

# _claudainer_is_unsafe_path <path>
# True if <path> is empty or could escape the directory it gets joined under
# (a literal ".." component). Shared by exclude_paths masking and the
# .claudainer "project:" validation.
_claudainer_is_unsafe_path() {
  case "$1" in
    ''|..|../*|*/../*|*/..) return 0 ;;
    *) return 1 ;;
  esac
}

# Create .claudainer with the default exclude_paths if it does not exist yet.
# A no-op if the file is already present (custom or previously created).
_claudainer_ensure_config_file() {
  if [ ! -e .claudainer ]; then
    { printf 'exclude_paths:\n'; printf '  - %s\n' "${_CLAUDAINER_DEFAULT_EXCLUDES[@]}"; } > .claudainer 2>/dev/null \
      && echo "claudainer: created .claudainer with default exclude_paths (.env, .env.local)" >&2
  fi
}

# Resolve the logical project name used to build a stable container path
# (instead of mirroring the host's own directory) from the .claudainer
# "project:" key. Empty means: mirror the host path — see claudainer().
# Sets _CLAUDAINER_PROJECT_NAME. Assumes .claudainer already exists (call
# _claudainer_ensure_config_file first).
_claudainer_resolve_project() {
  local name=""
  [ -f .claudainer ] && [ -r .claudainer ] && name="$(_claudainer_yaml_scalar .claudainer project)"

  name="${name#/}"
  if [ -n "$name" ] && _claudainer_is_unsafe_path "$name"; then
    echo "claudainer: ignoring unsafe '.claudainer' project value '$name'" >&2
    name=""
  fi
  _CLAUDAINER_PROJECT_NAME="$name"
}

# Populate _CLAUDAINER_CONFIG_MASK_ARGS with read-only masks for every path
# listed under exclude_paths in the project's .claudainer file, rooted at
# <container_workdir>. Files read as empty (/dev/null), directories appear
# empty (tmpfs). Assumes .claudainer already exists (call
# _claudainer_ensure_config_file first).
_claudainer_config_masks() {
  local container_workdir="$1"
  _CLAUDAINER_CONFIG_MASK_ARGS=()

  local val rel
  local paths=()
  if [ -f .claudainer ] && [ -r .claudainer ]; then
    while IFS= read -r val; do
      paths+=("$val")
    done < <(_claudainer_yaml_list .claudainer exclude_paths)
  else
    paths=("${_CLAUDAINER_DEFAULT_EXCLUDES[@]}")
  fi

  # Only mask paths that actually exist: the project directory is a bind mount
  # of the host cwd, so asking the runtime to mount over a missing target
  # would create an empty file/dir back on the host.
  for val in "${paths[@]}"; do
    rel="${val#./}"; rel="${rel#/}"
    if _claudainer_is_unsafe_path "$rel"; then
      echo "claudainer: ignoring unsafe exclude_path '$val'" >&2; continue
    fi
    if [ -d "$rel" ]; then
      _CLAUDAINER_CONFIG_MASK_ARGS+=(--tmpfs "$container_workdir/$rel")
    elif [ -e "$rel" ]; then
      _CLAUDAINER_CONFIG_MASK_ARGS+=(-v "/dev/null:$container_workdir/$rel:ro")
    fi
  done
}

claudainer() {
  local pull_flag=false
  local shell_flag=false
  local git_config_flag=false
  local claude_args=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --pull)   pull_flag=true; shift ;;
      --shell)  shell_flag=true; shift ;;
      --enable-git) git_config_flag=true; shift ;;
      --)       shift; claude_args+=("$@"); break ;;
      *)        claude_args+=("$1"); shift ;;
    esac
  done

  touch ~/.claude.json 2>/dev/null || true
  mkdir -p ~/.claude

  _claudainer_setup || return 1
  _claudainer_proxy_setup "$pull_flag" || return 1

  local _CLAUDAINER_CMD=()
  if [ "$shell_flag" = true ]; then
    _CLAUDAINER_CMD=(bash)
  else
    # Always run claude behind a PTY filter that strips terminal mouse-tracking,
    # so terminals like macOS Terminal.app keep normal text selection/copy.
    _CLAUDAINER_CMD=(claudainer-disable-mouse claude "${claude_args[@]}")
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

  _claudainer_ensure_config_file

  # Resolve where the project is mounted/worked from inside the container.
  # Default: mirror the host's absolute cwd, so Claude Code's session-storage
  # slug (~/.claude/projects/<slug>) matches what a native run would produce
  # and distinct projects don't collide under a single fixed "/workspace"
  # slug. Set the .claudainer "project:" key when several checkouts of the
  # same project — e.g. git worktrees — should share one stable slug instead
  # of fragmenting into one per checkout directory.
  local host_cwd="$(pwd)"
  local _CLAUDAINER_PROJECT_NAME=""
  _claudainer_resolve_project
  local container_workdir="$host_cwd"
  [ -n "$_CLAUDAINER_PROJECT_NAME" ] && container_workdir="/home/developer/projects/$_CLAUDAINER_PROJECT_NAME"

  local _CLAUDAINER_CONFIG_MASK_ARGS=()
  _claudainer_config_masks "$container_workdir"
  if [ "${#_CLAUDAINER_CONFIG_MASK_ARGS[@]}" -gt 0 ]; then
    echo "claudainer: excluding $(( ${#_CLAUDAINER_CONFIG_MASK_ARGS[@]} / 2 )) path(s) listed in .claudainer from the project directory" >&2
  fi

  local pull_arg=""
  [ "$pull_flag" = true ] && pull_arg="--pull=always"

  "$_CLAUDAINER_RUNTIME" run --rm -it $pull_arg \
    "${_CLAUDAINER_USER_ARGS[@]}" \
    "${_CLAUDAINER_NETWORK_ARGS[@]}" \
    "${_CLAUDAINER_PROXY_ARGS[@]}" \
    -v ~/.claude:/home/developer/.claude \
    -v ~/.claude.json:/home/developer/.claude.json \
    "${host_home_args[@]}" \
    "${git_config_args[@]}" \
    -v "$host_cwd":"$container_workdir" \
    -w "$container_workdir" \
    "${_CLAUDAINER_CONFIG_MASK_ARGS[@]}" \
    -e HOME=/home/developer \
    -e TERM="${TERM:-xterm-256color}" \
    ghcr.io/whatwedo/claudainer:latest \
    "${_CLAUDAINER_CMD[@]}"
}

unset _CLAUDAINER_DIR _CLAUDAINER_SELF
