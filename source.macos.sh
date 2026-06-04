#!/usr/bin/env bash
# macOS platform config for claudainer (sourced by source.sh).

_CLAUDAINER_RUNTIME=docker

_claudainer_setup() {
  local docker_flag="$1"
  _CLAUDAINER_USER_ARGS=(-u 1000:1000)
  if [ "$docker_flag" = true ]; then
    _CLAUDAINER_SOCKET_ARGS=(-v /var/run/docker.sock:/var/run/docker.sock)
  else
    _CLAUDAINER_SOCKET_ARGS=()
  fi
}
