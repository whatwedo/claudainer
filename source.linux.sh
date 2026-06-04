#!/usr/bin/env bash
# Linux implementation of the claudainer command (uses podman).

claudainer() {
  local pull_flag=""
  local docker_flag=false
  local claude_args=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --pull)
        pull_flag="--pull=always"
        shift
        ;;
      --docker)
        docker_flag=true
        shift
        ;;
      --)
        shift
        claude_args+=("$@")
        break
        ;;
      *)
        claude_args+=("$1")
        shift
        ;;
    esac
  done

  local socket_args=()
  if [ "$docker_flag" = true ]; then
    socket_args=(-v /var/run/docker.sock:/var/run/docker.sock)
  else
    systemctl --user start podman.socket
    socket_args=(-v "/var/run/user/$(id -u)/podman/podman.sock:/var/run/user/1000/podman/podman.sock")
  fi

  # Ensure credential files exist before mounting
  touch ~/.claude.json 2>/dev/null || true
  mkdir -p ~/.claude

  podman run --rm -it $pull_flag \
    "${socket_args[@]}" \
    -v ~/.claude:/home/developer/.claude \
    -v ~/.claude.json:/home/developer/.claude.json \
    -v "$(pwd)":/workspace \
    -e HOME=/home/developer \
    --userns=keep-id:uid=1000,gid=1000 \
    ghcr.io/whatwedo/claudainer:latest \
    claude "${claude_args[@]}"
}
