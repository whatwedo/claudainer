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

@test "starts proxy container when it does not exist" {
  _claudainer_proxy_setup
  assert_call_contains "run"
  assert_call_contains "claudainer-proxy"
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
