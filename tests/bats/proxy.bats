#!/usr/bin/env bats
# Tests for _claudainer_proxy_setup() and claudainer-proxy-stop() in source.sh

load 'helpers/stubs'

SOURCE_SH="$BATS_TEST_DIRNAME/../../source.sh"

setup() {
  setup_stubs
  make_runtime_stub podman
  make_stub docker "exit 1"  # docker absent — podman preferred
  source "$SOURCE_SH"
  export _CLAUDAINER_RUNTIME=podman
}

teardown() {
  teardown_stubs
  unset _CLAUDAINER_RUNTIME _CLAUDAINER_NETWORK_ARGS _CLAUDAINER_PROXY_ARGS
}

# --- _claudainer_proxy_setup: network args ---

@test "sets network args after setup" {
  _claudainer_proxy_setup
  [ "${_CLAUDAINER_NETWORK_ARGS[*]}" = "--network claudainer-net" ]
}

@test "sets HTTP_PROXY env arg" {
  _claudainer_proxy_setup
  local found=false
  for arg in "${_CLAUDAINER_PROXY_ARGS[@]}"; do
    [[ "$arg" == *"HTTP_PROXY=http://claudainer-proxy:3128"* ]] && found=true
  done
  [ "$found" = true ]
}

@test "sets HTTPS_PROXY env arg" {
  _claudainer_proxy_setup
  local found=false
  for arg in "${_CLAUDAINER_PROXY_ARGS[@]}"; do
    [[ "$arg" == *"HTTPS_PROXY=http://claudainer-proxy:3128"* ]] && found=true
  done
  [ "$found" = true ]
}

@test "sets NO_PROXY env arg" {
  _claudainer_proxy_setup
  local found=false
  for arg in "${_CLAUDAINER_PROXY_ARGS[@]}"; do
    [[ "$arg" == *"NO_PROXY=localhost,127.0.0.1"* ]] && found=true
  done
  [ "$found" = true ]
}

# --- _claudainer_proxy_setup: creates missing resources ---

@test "creates network when it does not exist" {
  _claudainer_proxy_setup
  assert_call_contains "network"
  assert_call_contains "create"
}

@test "starts proxy container with --rm when it does not exist" {
  _claudainer_proxy_setup
  assert_call_contains "run"
  assert_call_contains "--rm"
  assert_call_contains "claudainer-proxy"
}

@test "does not run proxy container when already running" {
  make_runtime_stub podman running
  _claudainer_proxy_setup
  assert_call_not_contains "run"
}

@test "removes and restarts a stale exited proxy container" {
  # A --rm container left behind by a host reboot lingers in "exited" state;
  # the setup must clear it and start a fresh one rather than assume it is up.
  make_runtime_stub podman exited
  _claudainer_proxy_setup
  assert_call_contains "rm"
  assert_call_contains "run"
  assert_call_contains "claudainer-proxy"
}

# --- _claudainer_proxy_setup: --pull ---

@test "pulls the latest proxy image when pull requested" {
  _claudainer_proxy_setup true
  assert_call_contains "pull"
  assert_call_contains "ghcr.io/whatwedo/claudainer-proxy:latest"
}

@test "restarts an already-running proxy when pull requested" {
  # A healthy proxy is left running on a normal launch, but --pull must replace
  # it so the freshly pulled image is actually picked up.
  make_runtime_stub podman running
  _claudainer_proxy_setup true
  assert_call_contains "rm"
  assert_call_contains "run"
}

@test "does not pull the proxy image without pull flag" {
  _claudainer_proxy_setup
  assert_call_not_contains "pull"
}

# --- claudainer-proxy-stop ---

@test "proxy-stop calls stop on the proxy container" {
  claudainer-proxy-stop
  assert_call_contains "stop"
  assert_call_contains "claudainer-proxy"
}

@test "proxy-stop calls rm on the proxy container" {
  claudainer-proxy-stop
  assert_call_contains "rm"
  assert_call_contains "claudainer-proxy"
}

@test "proxy-stop removes the network" {
  claudainer-proxy-stop
  assert_call_contains "network"
  assert_call_contains "rm"
  assert_call_contains "claudainer-net"
}

@test "proxy-stop returns 1 when no runtime is found" {
  run bash -c "
    command() { case \"\$1 \$2\" in '-v podman'|'-v docker') return 1;; *) builtin command \"\$@\";; esac; }
    source '$BATS_TEST_DIRNAME/../../source.sh'
    claudainer-proxy-stop
  "
  [ "$status" -eq 1 ]
}

@test "proxy-stop prints error when no runtime found" {
  run bash -c "
    command() { case \"\$1 \$2\" in '-v podman'|'-v docker') return 1;; *) builtin command \"\$@\";; esac; }
    source '$BATS_TEST_DIRNAME/../../source.sh'
    claudainer-proxy-stop 2>&1
  "
  [[ "$output" == *"neither podman nor docker"* ]]
}
