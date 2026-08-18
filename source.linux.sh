#!/usr/bin/env bash
# Linux platform config for claudainer (sourced by source.sh).

_claudainer_setup() {
  if command -v podman >/dev/null 2>&1; then
    _CLAUDAINER_RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then
    _CLAUDAINER_RUNTIME=docker
  else
    echo "claudainer: neither podman nor docker found in PATH" >&2
    return 1
  fi

  if [ "$_CLAUDAINER_RUNTIME" = podman ]; then
    _CLAUDAINER_USER_ARGS=(--userns=keep-id:uid=1000,gid=1000)
  else
    _CLAUDAINER_USER_ARGS=(--user 1000:1000)
  fi
}
