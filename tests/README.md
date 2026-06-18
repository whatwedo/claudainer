# Tests

Three layers of tests, each targeting a different surface. No tools need to be installed on the host — everything runs inside containers via `tests/bin/test.sh`.

## Quick start

```bash
# Build images and run all tests
make test

# Or step by step
make test-build       # build claudainer:local and claudainer-proxy:local
make test-bats        # shell script logic (no image required)
make test-cst         # image structure
make test-integration # runtime behaviour
```

By default `CLAUDAINER_IMAGE=claudainer:local` and `PROXY_IMAGE=claudainer-proxy:local`. Override to test a different image:

```bash
CLAUDAINER_IMAGE=ghcr.io/whatwedo/claudainer:latest make test-cst
```

All test commands require Docker. Integration tests additionally require Node.js 22+ installed on the host (they run natively, like CI).

---

## Shell tests (BATS)

Tests the shell script logic in `source.sh` and `source.linux.sh` — runtime detection, flag parsing, argument construction — without requiring a container image to be built.

**What's covered:**
- `linux_setup.bats` — `_claudainer_setup`: podman/docker detection, user namespace args, socket args
- `proxy.bats` — `_claudainer_proxy_setup` and `claudainer-proxy-stop`: network/container lifecycle, error handling
- `claudainer.bats` — `claudainer()` flag parsing: `--pull`, `--shell`, `--docker-socket`, `--git-config`, passthrough args, and `.claudainer` exclude_paths parsing / mask-arg construction

## Image structure tests

Validates the built image artifact — installed binaries, working directory, user, environment variables. Runs after building, before push. Uses `container-structure-test` with the configs in `tests/cst/`.

**What's covered (`claudainer`):** node v22, claude/docker/git/curl on PATH, user `developer`, workdir `/workspace`, `CLAUDE_CODE_DISABLE_AUTOUPDATER=1`, home and workspace dirs exist

**What's covered (`proxy`):** squid binary present and config file exists

## Integration tests (Testcontainers)

Starts real containers and verifies runtime behaviour — user identity, environment variables, filesystem mounts, and proxy network connectivity.

**Options:**
```bash
# skip the proxy network test (needs internet access)
SKIP_NETWORK_TESTS=1 make test-integration
```

**What's covered:**
- `claudainer.test.js` — claude binary present, node v22, docker CLI, running as `developer`, workdir `/workspace`, `CLAUDE_CODE_DISABLE_AUTOUPDATER=1`, filesystem write in `/workspace`, and `.env` masking (a `/dev/null`-masked `.env` reads empty while the host file is untouched)
- `network.test.js` — main container reaches `claudainer-proxy:3128` over a shared network and HTTP requests are forwarded
