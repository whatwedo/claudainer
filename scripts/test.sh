#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDAINER_IMAGE="${CLAUDAINER_IMAGE:-claudainer:local}"
PROXY_IMAGE="${PROXY_IMAGE:-claudainer-proxy:local}"

CR="${CONTAINER_RUNTIME:-}"
if [[ -z "$CR" ]]; then
  if command -v podman &>/dev/null; then
    CR=podman
  elif command -v docker &>/dev/null; then
    CR=docker
  else
    echo "ERROR: Neither podman nor docker found" >&2
    exit 1
  fi
fi

log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

image_exists() {
  "$CR" image inspect "$1" &>/dev/null
}

detect_socket() {
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    echo "${DOCKER_HOST#unix://}"
    return 0
  fi
  local xdg="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [[ -S "$xdg/podman/podman.sock" ]]; then echo "$xdg/podman/podman.sock"; return 0; fi
  if [[ -S "/run/podman/podman.sock" ]];  then echo "/run/podman/podman.sock";  return 0; fi
  if [[ -S "/var/run/docker.sock" ]];     then echo "/var/run/docker.sock";     return 0; fi
  die "No container socket found. For podman, run: systemctl --user start podman.socket"
}

# Run a command in a container and assert exit code 0 (and optionally match output).
_assert() {
  local image="$1" desc="$2" pattern="$3"
  shift 3
  local out exit_code=0
  out="$("$CR" run --rm "$image" "$@" 2>&1)" || exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    printf '  FAIL: %s\n' "$desc" >&2
    return 1
  fi
  if [[ -n "$pattern" ]] && ! echo "$out" | grep -q "$pattern"; then
    printf '  FAIL: %s (got: %s)\n' "$desc" "$out" >&2
    return 1
  fi
  printf '  PASS: %s\n' "$desc" >&2
}

run_build() {
  log "Building $CLAUDAINER_IMAGE..."
  "$CR" build -t "$CLAUDAINER_IMAGE" "$REPO_ROOT"
  log "Building $PROXY_IMAGE..."
  "$CR" build -t "$PROXY_IMAGE" "$REPO_ROOT/proxy"
}

run_bats() {
  log "Running BATS shell tests..."
  "$CR" run --rm \
    -v "$REPO_ROOT:/workspace:ro,z" \
    docker.io/bats/bats:latest \
    /workspace/tests/bats/
}

run_cst() {
  log "Running container structure tests..."
  local failed=0

  if ! image_exists "$CLAUDAINER_IMAGE"; then
    warn "Image '$CLAUDAINER_IMAGE' not found, skipping claudainer tests"
  else
    log "Testing $CLAUDAINER_IMAGE..."
    _assert "$CLAUDAINER_IMAGE" "node v22"              "v22\."      node --version                          || failed=1
    _assert "$CLAUDAINER_IMAGE" "claude binary"         ""           which claude                            || failed=1
    _assert "$CLAUDAINER_IMAGE" "docker CLI"            ""           docker --version                        || failed=1
    _assert "$CLAUDAINER_IMAGE" "git"                   ""           git --version                           || failed=1
    _assert "$CLAUDAINER_IMAGE" "curl"                  ""           curl --version                          || failed=1
    _assert "$CLAUDAINER_IMAGE" "user is developer"     "developer"  id -un                                  || failed=1
    _assert "$CLAUDAINER_IMAGE" "workdir is /workspace" "/workspace" pwd                                     || failed=1
    _assert "$CLAUDAINER_IMAGE" "autoupdater disabled"  "^1$"        printenv CLAUDE_CODE_DISABLE_AUTOUPDATER || failed=1
    _assert "$CLAUDAINER_IMAGE" "home dir exists"       ""           test -d /home/developer                 || failed=1
    _assert "$CLAUDAINER_IMAGE" "workspace dir exists"  ""           test -d /workspace                      || failed=1
  fi

  if ! image_exists "$PROXY_IMAGE"; then
    warn "Image '$PROXY_IMAGE' not found, skipping proxy tests"
  else
    log "Testing $PROXY_IMAGE..."
    _assert "$PROXY_IMAGE" "squid installed"  "" squid -v                     || failed=1
    _assert "$PROXY_IMAGE" "squid binary"     "" test -f /usr/sbin/squid      || failed=1
    _assert "$PROXY_IMAGE" "squid config"     "" test -f /etc/squid/squid.conf || failed=1
  fi

  [[ "$failed" -eq 0 ]] || die "CST tests failed"
}

run_integration() {
  log "Running integration tests..."
  local socket
  socket="$(detect_socket)"
  local userns=()
  [[ "$CR" == "podman" ]] && userns=(--userns=keep-id)

  "$CR" run --rm \
    "${userns[@]}" \
    -v "$REPO_ROOT/tests/integration:/app:z" \
    -v "$socket:/var/run/docker.sock" \
    -w /app \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e "CLAUDAINER_IMAGE=${CLAUDAINER_IMAGE}" \
    -e "CLAUDAINER_PROXY_IMAGE=${PROXY_IMAGE}" \
    docker.io/library/node:22 \
    sh -c "npm install && npm test"
}

SUITE="${1:-all}"

case "$SUITE" in
  build)       run_build ;;
  bats)        run_bats ;;
  cst)         run_cst ;;
  integration) run_integration ;;
  all)
    run_build
    run_bats
    run_cst
    run_integration
    ;;
  *)
    echo "Usage: $0 [build|bats|cst|integration|all]" >&2
    exit 1
    ;;
esac
