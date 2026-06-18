#!/usr/bin/env bats
# Tests for claudainer() flag parsing in source.sh

load 'helpers/stubs'

SOURCE_SH="$BATS_TEST_DIRNAME/../../source.sh"

setup() {
  setup_stubs
  make_runtime_stub podman
  make_stub docker "exit 1"

  # Isolated HOME so claudainer's touch/mkdir don't affect the real home dir
  export HOME="$(mktemp -d)"

  # Isolated, empty working dir so the .env scan is fast and deterministic
  # (claudainer scans the current directory for .env files to mask)
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"

  source "$SOURCE_SH"

  # Override proxy setup so only the final "run" call is recorded
  _claudainer_proxy_setup() {
    _CLAUDAINER_NETWORK_ARGS=()
    _CLAUDAINER_PROXY_ARGS=()
  }
}

teardown() {
  teardown_stubs
  cd /
  rm -rf "$HOME" "$WORKDIR"
  unset _CLAUDAINER_RUNTIME _CLAUDAINER_USER_ARGS _CLAUDAINER_SOCKET_ARGS
  unset _CLAUDAINER_NETWORK_ARGS _CLAUDAINER_PROXY_ARGS
}

# Helper: last token in the calls file (the final command argument)
last_call_token() {
  # Each arg is written on its own line; grab the last non-empty line
  grep -v '^$' "$CALLS_FILE" | tail -1
}

# --- Default invocation ---

@test "default invocation includes run --rm" {
  claudainer
  assert_call_contains "run"
  assert_call_contains "--rm"
}

@test "default command ends with claude" {
  claudainer
  [ "$(last_call_token)" = "claude" ]
}

# --- --pull flag ---

@test "--pull adds --pull=always" {
  claudainer --pull
  assert_call_contains "--pull=always"
}

@test "without --pull flag there is no --pull=always" {
  claudainer
  assert_call_not_contains "--pull=always"
}

# --- --shell flag ---

@test "--shell sets command to bash" {
  claudainer --shell
  assert_call_contains "bash"
}

@test "--shell final token is bash not claude" {
  claudainer --shell
  [ "$(last_call_token)" = "bash" ]
}

# --- --docker-socket / --ds flag ---

@test "--docker-socket mounts the docker socket" {
  claudainer --docker-socket
  assert_call_contains "/var/run/docker.sock"
}

@test "--ds short form mounts the docker socket" {
  claudainer --ds
  assert_call_contains "/var/run/docker.sock"
}

@test "without --ds no docker socket is mounted" {
  claudainer
  assert_call_not_contains "/var/run/docker.sock"
}

# --- passthrough args after -- ---

@test "args after -- are forwarded" {
  claudainer -- --dangerously-skip-permissions
  assert_call_contains "--dangerously-skip-permissions"
}

@test "multiple args after -- are all forwarded" {
  claudainer -- foo bar
  assert_call_contains "foo"
  assert_call_contains "bar"
}

# --- positional args ---

@test "positional args are forwarded to claude" {
  claudainer chat
  assert_call_contains "chat"
}

# --- mandatory flags always present ---

@test "workspace is mounted as /workspace" {
  claudainer
  assert_call_contains "/workspace"
}

@test "HOME env var is set to /home/developer inside container" {
  claudainer
  assert_call_contains "HOME=/home/developer"
}

# --- --git-config / --gc flag ---

@test "--git-config mounts gitconfig when file exists" {
  touch "$HOME/.gitconfig"
  claudainer --git-config
  assert_call_contains ".gitconfig"
}

@test "without --git-config no gitconfig is mounted" {
  touch "$HOME/.gitconfig"
  claudainer
  assert_call_not_contains ".gitconfig"
}

# --- .env masking / --include-env flag ---

@test ".env in the project is masked by default" {
  printf 'SECRET=1\n' > .env
  claudainer
  assert_call_contains "/dev/null:/workspace/.env:ro"
}

@test "nested .env is masked at its relative path" {
  mkdir -p sub
  printf 'SECRET=1\n' > sub/.env
  claudainer
  assert_call_contains "/dev/null:/workspace/sub/.env:ro"
}

@test "--include-env disables .env masking" {
  printf 'SECRET=1\n' > .env
  claudainer --include-env
  assert_call_not_contains "/dev/null:/workspace"
}

@test ".env.example template is not masked" {
  printf 'SECRET=\n' > .env.example
  claudainer
  assert_call_not_contains "/dev/null:/workspace"
}

@test "no .env files means no masking and no error" {
  claudainer
  assert_call_contains "run"
  assert_call_not_contains "/dev/null:/workspace"
}
