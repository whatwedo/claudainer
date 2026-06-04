#!/usr/bin/env bash
# macOS implementation of the claudainer command (uses docker).

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
  fi

  # Ensure credential files exist before mounting
  touch ~/.claude.json 2>/dev/null || true
  mkdir -p ~/.claude

  docker run --rm -it $pull_flag \
    "${socket_args[@]}" \
    -v ~/.claude:/home/developer/.claude \
    -v ~/.claude.json:/home/developer/.claude.json \
    -v "$(pwd)":/workspace \
    -e HOME=/home/developer \
    -u 1000:1000 \
    ghcr.io/whatwedo/claudainer:latest \
    claude "${claude_args[@]}"
}
