# Tests

Three layers of tests, each targeting a different surface. No tools need to be installed on the host — everything runs inside containers via `scripts/test.sh`.

## Quick start

```bash
# Build images and run all tests
./scripts/test.sh

# Or step by step
./scripts/test.sh build       # build claudainer:local and claudainer-proxy:local
./scripts/test.sh bats        # shell script logic (no image required)
./scripts/test.sh cst         # image structure
./scripts/test.sh integration # runtime behaviour
```

By default `CLAUDAINER_IMAGE=claudainer:local` and `PROXY_IMAGE=claudainer-proxy:local`. Override to test a different image:

```bash
CLAUDAINER_IMAGE=ghcr.io/whatwedo/claudainer:latest ./scripts/test.sh cst
```

All test commands require Docker. Integration tests additionally need the Docker daemon socket at `/var/run/docker.sock`.

---

## Shell tests (BATS)

Tests the shell script logic in `source.sh` and `source.linux.sh` — runtime detection, flag parsing, argument construction — without requiring a container image to be built.

**What's covered:**
- `linux_setup.bats` — `_claudainer_setup`: podman/docker detection, user namespace args, socket args
- `proxy.bats` — `_claudainer_proxy_setup` and `claudainer-proxy-stop`: network/container lifecycle, error handling
- `claudainer.bats` — `claudainer()` flag parsing: `--pull`, `--shell`, `--docker-socket`, `--git-config`, passthrough args

## Image structure tests

Validates the built image artifact — installed binaries, working directory, user, environment variables. Runs after building, before push. Uses `container-structure-test` with the configs in `tests/cst/`.

**What's covered (`claudainer`):** node v22, claude/docker/git/curl on PATH, user `developer`, workdir `/workspace`, `CLAUDE_CODE_DISABLE_AUTOUPDATER=1`, home and workspace dirs exist

**What's covered (`proxy`):** squid binary present and config file exists

## Integration tests (Testcontainers)

Starts real containers and verifies runtime behaviour — user identity, environment variables, filesystem mounts, and proxy network connectivity.

**Options:**
```bash
# skip the proxy network test (needs internet access)
SKIP_NETWORK_TESTS=1 ./scripts/test.sh integration
```

**What's covered:**
- `claudainer.test.js` — claude binary present, node v22, docker CLI, running as `developer`, workdir `/workspace`, `CLAUDE_CODE_DISABLE_AUTOUPDATER=1`, filesystem write in `/workspace`
- `network.test.js` — main container reaches `claudainer-proxy:3128` over a shared network and HTTP requests are forwarded
