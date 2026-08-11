#!/usr/bin/env bash
# Linux platform config for claudainer (sourced by source.sh).

_claudainer_setup() {
  local docker_flag="$1"

  if command -v podman >/dev/null 2>&1; then
    _CLAUDAINER_RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then
    _CLAUDAINER_RUNTIME=docker
  else
    echo "claudainer: neither podman nor docker found in PATH" >&2
    return 1
  fi

  if [ "$_CLAUDAINER_RUNTIME" = podman ]; then
    # User namespaces implicitly grant mount capabilities inside the container.
    _CLAUDAINER_USER_ARGS=(--userns=keep-id:uid=1000,gid=1000)
  else
    # SYS_ADMIN lets the entrypoint bind-mount masked paths inside the container
    # without touching the host filesystem, avoiding Docker Desktop VirtioFS
    # creating stub files when mounts are layered from the host side.
    _CLAUDAINER_USER_ARGS=(--cap-add SYS_ADMIN)
  fi

  if [ "$docker_flag" = true ]; then
    _CLAUDAINER_SOCKET_ARGS=(-v /var/run/docker.sock:/var/run/docker.sock)
  else
    _CLAUDAINER_SOCKET_ARGS=()
  fi
}
