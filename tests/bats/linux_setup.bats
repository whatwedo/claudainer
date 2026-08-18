#!/usr/bin/env bats
# Tests for _claudainer_setup() defined in source.linux.sh

load 'helpers/stubs'

setup() {
  setup_stubs
  # Source just the platform file — defines _claudainer_setup without side effects
  source "$BATS_TEST_DIRNAME/../../source.linux.sh"
}

teardown() {
  teardown_stubs
  unset _CLAUDAINER_RUNTIME _CLAUDAINER_USER_ARGS
}

# --- Runtime detection ---

@test "detects podman as primary runtime" {
  make_stub podman "exit 0"
  make_stub docker "exit 0"
  _claudainer_setup
  [ "$_CLAUDAINER_RUNTIME" = "podman" ]
}

@test "falls back to docker when podman is absent" {
  make_stub docker "exit 0"
  hide_command podman
  _claudainer_setup
  [ "$_CLAUDAINER_RUNTIME" = "docker" ]
}

@test "returns 1 when neither podman nor docker is found" {
  run bash -c "
    command() { case \"\$1 \$2\" in '-v podman'|'-v docker') return 1;; *) builtin command \"\$@\";; esac; }
    source '$BATS_TEST_DIRNAME/../../source.linux.sh'
    _claudainer_setup
  "
  [ "$status" -eq 1 ]
}

@test "prints error to stderr when no runtime is found" {
  run bash -c "
    command() { case \"\$1 \$2\" in '-v podman'|'-v docker') return 1;; *) builtin command \"\$@\";; esac; }
    source '$BATS_TEST_DIRNAME/../../source.linux.sh'
    _claudainer_setup 2>&1
  "
  [[ "$output" == *"neither podman nor docker"* ]]
}

# --- User namespace args ---

@test "sets keep-id userns args for podman" {
  make_stub podman "exit 0"
  _claudainer_setup
  [ "${_CLAUDAINER_USER_ARGS[*]}" = "--userns=keep-id:uid=1000,gid=1000" ]
}

@test "sets --user flag for docker" {
  make_stub docker "exit 0"
  hide_command podman
  _claudainer_setup
  [ "${_CLAUDAINER_USER_ARGS[*]}" = "--user 1000:1000" ]
}
