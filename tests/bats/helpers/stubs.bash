#!/usr/bin/env bash
# Shared BATS helpers: PATH-based command stubbing

setup_stubs() {
  STUB_DIR="$(mktemp -d)"
  CALLS_FILE="$STUB_DIR/calls"
  export PATH="$STUB_DIR:$PATH"
}

teardown_stubs() {
  rm -rf "$STUB_DIR"
}

# hide_command <name>  — makes `command -v <name>` return 1, simulating absence from PATH
hide_command() {
  _HIDDEN_CMD="$1"
  command() { [[ "$1 $2" == "-v $_HIDDEN_CMD" ]] && return 1; builtin command "$@"; }
}

# make_stub <name> <body>  — creates a simple stub
make_stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUB_DIR/$1"
  chmod +x "$STUB_DIR/$1"
}

# make_runtime_stub <name>
# Creates a container-runtime stub that:
#   - records every call as newline-separated args to $CALLS_FILE
#   - returns 1 for "network inspect" and "inspect" (simulates missing resources)
#   - returns 0 for everything else
make_runtime_stub() {
  local name="$1"
  cat > "$STUB_DIR/$name" <<STUBEOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "${CALLS_FILE}"
case "\$1" in
  network) [[ "\$2" == "inspect" ]] && exit 1; exit 0 ;;
  inspect) exit 1 ;;
  *) exit 0 ;;
esac
STUBEOF
  chmod +x "$STUB_DIR/$name"
}

# assert_call_contains <pattern>
# Checks that the calls file contains the given string
assert_call_contains() {
  grep -qF -- "$1" "$CALLS_FILE" \
    || { echo "Expected call containing: $1"; echo "Actual calls:"; cat "$CALLS_FILE"; return 1; }
}

# assert_call_not_contains <pattern>
assert_call_not_contains() {
  if grep -qF -- "$1" "$CALLS_FILE" 2>/dev/null; then
    echo "Expected NO call containing: $1"
    echo "Actual calls:"
    cat "$CALLS_FILE"
    return 1
  fi
}
