#!/bin/sh
# squid drops to the 'proxy' user before opening log files, so /dev/stdout
# must be world-writable at startup (container starts as root).
chmod 0666 /dev/stdout /dev/stderr 2>/dev/null || true
exec squid -N "$@"
