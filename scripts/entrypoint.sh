#!/usr/bin/env bash
set -e

# Apply masks from CLAUDAINER_EXCLUDE_PATHS (newline-separated relative paths).
# Running here — inside the container, as root — means the bind-mounts are pure
# Linux kernel operations and never touch the host filesystem. This prevents
# Docker Desktop (VirtioFS) from creating empty stub files in the project
# directory when mounts would otherwise be layered from the host side.
if [ -n "${CLAUDAINER_EXCLUDE_PATHS:-}" ]; then
  while IFS= read -r rel || [ -n "$rel" ]; do
    [ -z "$rel" ] && continue
    target="/workspace/$rel"
    if [ -d "$target" ]; then
      mount -t tmpfs tmpfs "$target"
    elif [ -e "$target" ]; then
      mount --bind /dev/null "$target"
      mount -o remount,ro,bind "$target"
    fi
  done <<< "$CLAUDAINER_EXCLUDE_PATHS"
fi

exec gosu developer "$@"
