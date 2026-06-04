#!/usr/bin/env bash
# Linux platform config for claudainer (sourced by source.sh).

_CLAUDAINER_RUNTIME=podman

_claudainer_setup() {
  local docker_flag="$1"
  _CLAUDAINER_USER_ARGS=(--userns=keep-id:uid=1000,gid=1000)
  if [ "$docker_flag" = true ]; then
    _CLAUDAINER_SOCKET_ARGS=(-v /var/run/docker.sock:/var/run/docker.sock)
  else
    _CLAUDAINER_SOCKET_ARGS=()
  fi
}
