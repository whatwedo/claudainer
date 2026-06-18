#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

CLAUDAINER_IMAGE="${CLAUDAINER_IMAGE:-claudainer:local}"
PROXY_IMAGE="${PROXY_IMAGE:-claudainer-proxy:local}"

log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

image_exists() {
  docker image inspect "$1" &>/dev/null
}

_cst_binary() {
  local bin="$TMPDIR_WORK/container-structure-test"
  [[ -f "$bin" ]] && { echo "$bin"; return; }

  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  [[ "$arch" == "x86_64" ]]  && arch="amd64"
  [[ "$arch" == "aarch64" ]] && arch="arm64"

  log "Downloading container-structure-test..."
  curl -fsSL -o "$bin" \
    "https://github.com/GoogleContainerTools/container-structure-test/releases/download/v1.22.1/container-structure-test-${os}-${arch}"
  chmod +x "$bin"
  echo "$bin"
}

_cst_for_image() {
  local image="$1" config="$2" cst="$3"

  if ! image_exists "$image"; then
    warn "Image '$image' not found, skipping $(basename "$config")"
    return 0
  fi

  "$cst" test --image "$image" --config "$config"
}

run_build() {
  log "Building $CLAUDAINER_IMAGE..."
  docker build -f "$REPO_ROOT/Containerfile" -t "$CLAUDAINER_IMAGE" "$REPO_ROOT"
  log "Building $PROXY_IMAGE..."
  docker build -f "$REPO_ROOT/proxy/Containerfile" -t "$PROXY_IMAGE" "$REPO_ROOT/proxy"
}

run_bats() {
  log "Running BATS shell tests..."
  docker run --rm \
    -v "$REPO_ROOT:/workspace:ro" \
    docker.io/bats/bats:latest \
    /workspace/tests/bats/
}

run_cst() {
  log "Running container structure tests..."
  local cst failed=0
  cst="$(_cst_binary)"

  _cst_for_image "$CLAUDAINER_IMAGE" "$REPO_ROOT/tests/cst/claudainer.yaml" "$cst" || failed=1
  _cst_for_image "$PROXY_IMAGE"      "$REPO_ROOT/tests/cst/proxy.yaml"      "$cst" || failed=1

  [[ "$failed" -eq 0 ]] || die "CST tests failed"
}

run_integration() {
  log "Running integration tests..."
  command -v node &>/dev/null || die "node is required for integration tests (install Node.js 22+)"
  cd "$REPO_ROOT/tests/integration"
  npm install
  CLAUDAINER_IMAGE="$CLAUDAINER_IMAGE" \
  CLAUDAINER_PROXY_IMAGE="$PROXY_IMAGE" \
  TESTCONTAINERS_RYUK_DISABLED=true \
  npm test
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
