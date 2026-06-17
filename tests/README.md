# Tests

Three layers of tests, each targeting a different surface.

## Shell tests (BATS)

Tests the shell script logic in `source.sh` and `source.linux.sh` — runtime detection, flag parsing, argument construction — without requiring a container runtime.

**Install BATS:**
```bash
sudo apt-get install -y bats   # Debian/Ubuntu
npm install -g bats            # npm
brew install bats-core         # macOS
```

**Run:**
```bash
bats tests/bats/
```

**What's covered:**
- `linux_setup.bats` — `_claudainer_setup`: podman/docker detection, user namespace args, socket args
- `proxy.bats` — `_claudainer_proxy_setup` and `claudainer-proxy-stop`: network/container lifecycle, error handling
- `claudainer.bats` — `claudainer()` flag parsing: `--pull`, `--shell`, `--docker-socket`, `--git-config`, passthrough args

## Image structure tests (container-structure-test)

Validates the built image artifact — installed binaries, working directory, user, environment variables. Runs after `podman build`, before push.

**Install:**
```bash
VERSION=v1.22.1  # check https://github.com/GoogleContainerTools/container-structure-test/releases
BASE=https://github.com/GoogleContainerTools/container-structure-test/releases/download/${VERSION}
curl -fsSL "${BASE}/container-structure-test-linux-amd64" -o container-structure-test
curl -fsSL "${BASE}/container-structure-test-linux-amd64.sha256" -o container-structure-test.sha256
echo "$(cat container-structure-test.sha256)  container-structure-test" | sha256sum -c -
chmod +x container-structure-test && sudo mv container-structure-test /usr/local/bin/container-structure-test
```

**Run:**
```bash
podman build -t claudainer:local .
container-structure-test test --image claudainer:local --config tests/cst/claudainer.yaml

podman build -t claudainer-proxy:local proxy/
container-structure-test test --image claudainer-proxy:local --config tests/cst/proxy.yaml
```

**What's covered (`claudainer.yaml`):** node v22, claude/docker/git/curl on PATH, user `developer`, workdir `/workspace`, `CLAUDE_CODE_DISABLE_AUTOUPDATER=1`

**What's covered (`proxy.yaml`):** squid binary and config file present

## Integration tests (Testcontainers)

Starts real containers and verifies runtime behavior — user identity, environment variables, filesystem mounts, and proxy network connectivity. Requires Docker and a published or locally-built image.

**Install:**
```bash
cd tests/integration && npm install
```

**Run:**
```bash
# against the published image
npm test

# against a locally-built image
CLAUDAINER_IMAGE=claudainer:local npm test

# skip the proxy network test (needs internet access)
SKIP_NETWORK_TESTS=1 npm test
```

**What's covered:**
- `claudainer.test.js` — claude binary present, node v22, docker CLI, running as `developer`, workdir `/workspace`, `CLAUDE_CODE_DISABLE_AUTOUPDATER=1`, filesystem write in `/workspace`
- `network.test.js` — main container reaches `claudainer-proxy:3128` over a shared network and HTTP requests are forwarded
