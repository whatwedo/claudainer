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
    # keep-id maps the host user to container uid 1000 (developer), so files
    # written by gosu'd processes stay owned by the host user. Start as
    # container root so the entrypoint can mount the exclude masks and then
    # drop to developer via gosu. SYS_ADMIN is only namespaced in rootless mode.
    _CLAUDAINER_USER_ARGS=(--userns=keep-id:uid=1000,gid=1000 --user 0:0 --cap-add SYS_ADMIN)
  else
    # SYS_ADMIN lets the entrypoint bind-mount masked paths inside the container
    # without touching the host filesystem, avoiding Docker Desktop VirtioFS
    # creating stub files when mounts are layered from the host side.
    _CLAUDAINER_USER_ARGS=(--cap-add SYS_ADMIN)
  fi
}
