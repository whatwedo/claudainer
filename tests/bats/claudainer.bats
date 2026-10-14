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
  unset _CLAUDAINER_RUNTIME _CLAUDAINER_USER_ARGS
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

@test "project directory is mounted at the host cwd by default" {
  claudainer
  assert_call_contains "$WORKDIR:$WORKDIR"
}

@test "container workdir is set to the host cwd by default" {
  claudainer
  assert_call_contains "-w"
  assert_call_contains "$WORKDIR"
}

@test "HOME env var is set to /home/developer inside container" {
  claudainer
  assert_call_contains "HOME=/home/developer"
}

# --- --enable-git flag ---

@test "--enable-git mounts gitconfig when file exists" {
  touch "$HOME/.gitconfig"
  claudainer --enable-git
  assert_call_contains ".gitconfig"
}

@test "without --enable-git no gitconfig is mounted" {
  touch "$HOME/.gitconfig"
  claudainer
  assert_call_not_contains ".gitconfig"
}

# --- mouse-tracking filter (always on) ---

@test "claude is always wrapped with the mouse filter" {
  claudainer
  assert_call_contains "claudainer-disable-mouse"
}

@test "the wrapped command is still claude" {
  claudainer
  [ "$(last_call_token)" = "claude" ]
}

@test "the --shell bash command is not wrapped with the mouse filter" {
  claudainer --shell
  assert_call_not_contains "claudainer-disable-mouse"
  [ "$(last_call_token)" = "bash" ]
}

# --- .claudainer exclude_paths masking ---

@test "creates .claudainer with default exclude_paths when absent" {
  claudainer
  [ -f .claudainer ]
  grep -qF -- ".env" .claudainer
  grep -qF -- ".env.local" .claudainer
}

@test "default .env and .env.local are masked when they exist" {
  printf 'SECRET=1\n' > .env
  printf 'SECRET=2\n' > .env.local
  claudainer
  assert_call_contains "/dev/null:$WORKDIR/.env:ro"
  assert_call_contains "/dev/null:$WORKDIR/.env.local:ro"
}

@test "a listed path that does not exist is not masked and no host file is created" {
  # The auto-created .claudainer lists .env and .env.local, but neither exists.
  claudainer
  assert_call_not_contains "/dev/null:$WORKDIR/.env:ro"
  [ ! -e .env ]
  [ ! -e .env.local ]
}

@test "an existing .claudainer is not overwritten" {
  printf 'exclude_paths:\n  - secret.txt\n' > .claudainer
  printf 'SECRET=1\n' > secret.txt
  printf 'SECRET=1\n' > .env
  claudainer
  # Custom config is preserved; defaults were not appended
  grep -qF -- "secret.txt" .claudainer
  ! grep -qF -- ".env.local" .claudainer
  # secret.txt is masked, but .env (not listed) is not
  assert_call_contains "/dev/null:$WORKDIR/secret.txt:ro"
  assert_call_not_contains "/dev/null:$WORKDIR/.env:ro"
}

@test "a listed directory is masked via tmpfs" {
  mkdir secrets
  printf 'exclude_paths:\n  - secrets/\n' > .claudainer
  claudainer
  assert_call_contains "--tmpfs"
  assert_call_contains "$WORKDIR/secrets"
}

@test "quoted entries and inline comments are parsed" {
  printf 'exclude_paths:\n  - "with space.txt"  # a comment\n' > .claudainer
  printf 'x\n' > "with space.txt"
  claudainer
  assert_call_contains "/dev/null:$WORKDIR/with space.txt:ro"
}

@test "unsafe traversal entries are ignored" {
  printf 'exclude_paths:\n  - ../escape\n' > .claudainer
  claudainer
  assert_call_contains "run"
  assert_call_not_contains "$WORKDIR/../"
}

# --- .claudainer "project:" key ---

@test "a .claudainer project key mounts and sets workdir under /home/developer/projects" {
  printf 'exclude_paths:\n  - .env\nproject: whatwedo/claudainer\n' > .claudainer
  claudainer
  assert_call_contains "$WORKDIR:/home/developer/projects/whatwedo/claudainer"
  assert_call_contains "/home/developer/projects/whatwedo/claudainer"
}

@test "an unsafe .claudainer project value is ignored and falls back to the default mount" {
  printf 'project: ../escape\n' > .claudainer
  claudainer
  assert_call_contains "run"
  assert_call_not_contains "/home/developer/projects"
  assert_call_contains "$WORKDIR:$WORKDIR"
}
