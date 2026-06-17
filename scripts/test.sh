#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDAINER_IMAGE="${CLAUDAINER_IMAGE:-claudainer:local}"
PROXY_IMAGE="${PROXY_IMAGE:-claudainer-proxy:local}"
CST_VERSION="${CST_VERSION:-v1.22.1}"
CST_HELPER_IMAGE="claudainer-cst:local"

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

TMPDIR_WORK=""
cleanup() {
  [[ -n "$TMPDIR_WORK" ]] && rm -rf "$TMPDIR_WORK"
}
trap cleanup EXIT

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

image_exists() {
  "$CR" image inspect "$1" &>/dev/null
}

build_cst_image() {
  if image_exists "$CST_HELPER_IMAGE"; then
    return 0
  fi
  log "Building CST helper image $CST_HELPER_IMAGE..."
  "$CR" build \
    --build-arg "CST_VERSION=${CST_VERSION}" \
    -t "$CST_HELPER_IMAGE" \
    - <<'CONTAINEREOF'
FROM docker.io/library/debian:stable-slim
ARG CST_VERSION=v1.22.1
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
        ca-certificates curl && \
    BASE="https://github.com/GoogleContainerTools/container-structure-test/releases/download/${CST_VERSION}" && \
    curl -fsSL "${BASE}/container-structure-test-linux-amd64" \
        -o /usr/local/bin/container-structure-test && \
    curl -fsSL "${BASE}/checksums.txt" -o /tmp/checksums.txt && \
    grep "container-structure-test-linux-amd64" /tmp/checksums.txt \
        | sed 's|container-structure-test-linux-amd64|/usr/local/bin/container-structure-test|' \
        | sha256sum -c - && \
    chmod +x /usr/local/bin/container-structure-test && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/checksums.txt
ENTRYPOINT ["/usr/local/bin/container-structure-test"]
CONTAINEREOF
}

detect_socket() {
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    echo "${DOCKER_HOST#unix://}"
    return 0
  fi
  local xdg="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [[ -S "$xdg/podman/podman.sock" ]]; then
    echo "$xdg/podman/podman.sock"
    return 0
  fi
  if [[ -S "/run/podman/podman.sock" ]]; then
    echo "/run/podman/podman.sock"
    return 0
  fi
  if [[ -S "/var/run/docker.sock" ]]; then
    echo "/var/run/docker.sock"
    return 0
  fi
  die "No container socket found. For podman, run: systemctl --user start podman.socket"
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

_cst_for_image() {
  local image="$1"
  local config="$2"

  if ! image_exists "$image"; then
    warn "Image '$image' not found, skipping $(basename "$config")"
    return 0
  fi

  log "Running CST for $image..."
  "$CR" save "$image" -o "$TMPDIR_WORK/image.tar"
  "$CR" run --rm \
    -v "$TMPDIR_WORK:/tmp/cst-work:z" \
    -v "$REPO_ROOT/tests/cst:/tests/cst:ro,z" \
    "$CST_HELPER_IMAGE" \
    test \
    --driver tar \
    --image /tmp/cst-work/image.tar \
    --config "/tests/cst/$(basename "$config")"
}

run_cst() {
  log "Running container structure tests..."
  TMPDIR_WORK="$(mktemp -d)"
  build_cst_image
  _cst_for_image "$CLAUDAINER_IMAGE" "$REPO_ROOT/tests/cst/claudainer.yaml"
  _cst_for_image "$PROXY_IMAGE" "$REPO_ROOT/tests/cst/proxy.yaml"
}

run_integration() {
  log "Running integration tests..."
  local socket
  socket="$(detect_socket)"

  "$CR" run --rm \
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
