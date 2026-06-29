# Claudainer

Container image that runs [Claude Code](https://claude.ai/code) as an isolated, per-project agent.

```
    host: your project dir + ~/.claude credentials
                          │
                          │  claudainer
                          ▼
      ┌──────────────────────────────────────┐
      │         claudainer container         │
      │   ┌──────────────────────────────┐   │
      │   │      Claude Code agent       │   │
      │   └──────────────────────────────┘   │
      │   /workspace    ← your cwd (rw)      │
      │   ~/.claude     ← creds (ro)         │
      │   .claudainer   ← project config     │
      └──────────────────────────────────────┘
                          │
                          │  all outbound traffic
                          ▼
      ┌──────────────────────────────────────┐
      │      claudainer-proxy  (Squid)       │
      │      allow / block lists             │
      └──────────────────────────────────────┘
                          │
                          ▼
      internet  (Anthropic API, GitHub, npm, …)
```

## What's inside

- `debian:stable-slim` base
- user `developer` (UID 1000) with home at `/home/developer`
- Claude Code installed globally via npm
- Docker CLI installed (for `--enable-docker` flag support)
- `/workspace` as the working directory

## Setup

Add the following to your `.bashrc` or `.zshrc`:

```bash
source <(curl -s https://raw.githubusercontent.com/whatwedo/claudainer/refs/heads/main/source.sh)
```

This provides the `claudainer` command in your shell.

## Usage

```bash
claudainer [options] [claude args]
```

Run `claudainer` from any project directory. Your current directory is mounted as `/workspace` inside the container. Claude credentials (`~/.claude` and `~/.claude.json`) are shared from your host so login is only required once.

### Options

| Flag | Description |
|------|-------------|
| `--pull` | Pull the latest claudainer and proxy images before running |
| `--enable-docker` | Mount the Docker socket into the container |
| `--shell` | Start a bash shell instead of Claude Code |
| `--enable-git` | Mount `~/.gitconfig` and `~/.config/git/` (read-only) into the container |

### Examples

```bash
# Start Claude Code in the current directory
claudainer

# Pass arguments to claude
claudainer --dangerously-skip-permissions

# Mount Docker socket (e.g. for Docker-aware tasks)
claudainer --enable-docker

# Pull latest image and start
claudainer --pull

# Open a bash shell in the container (without starting Claude Code)
claudainer --shell

# Mount git config so git identity/settings are available inside the container
claudainer --enable-git
```

## Project configuration (`.claudainer`)

Each project can control which paths are hidden from the agent via a
`.claudainer` file (YAML) in the project root. The first time you run
`claudainer` in a project, the file is created automatically with sensible
defaults:

```yaml
exclude_paths:
  - .env
  - .env.local
```

Every path under `exclude_paths` is excluded from `/workspace` so secrets it may
contain are not exposed to the agent:

- **Files** are masked with a read-only empty mount, so they read as empty inside
  the container.
- **Directories** are mounted as an empty `tmpfs`, so their contents are hidden.

In both cases the real files on your host are left untouched. Entries are
**literal paths relative to the project root** (no wildcards), e.g.:

```yaml
exclude_paths:
  - .env
  - .env.local
  - secrets/
  - config/credentials.json
```

Edit `.claudainer` to add or remove excluded paths — to mount a real `.env` file
(e.g. when an app or dev server inside the container needs it at runtime), simply
remove it from the list. The `.claudainer` file itself stays visible in
`/workspace`; commit it or add it to `.gitignore` as you prefer.

## Proxy

Every `claudainer` run automatically routes outgoing traffic through a Squid proxy container (`claudainer-proxy`). The proxy is started on first use and reused across invocations — you don't need to do anything to enable it.

This makes it straightforward to add URL allow/block lists in a future step by editing `proxy/squid.conf`:

```
# Allow only specific hosts (example — not active by default)
acl allowed_sites dstdomain .anthropic.com .github.com
http_access allow CONNECT allowed_sites
http_access allow allowed_sites
http_access deny all
```

To stop and remove the proxy container and its network:

```bash
claudainer-proxy-stop
```

## How it works

`source.sh` detects your OS and sources the appropriate platform file:

The platform file detects the available container runtime, preferring `podman` over `docker`. With `podman` your user ID is mapped to UID 1000 inside the container via `--userns=keep-id`; with `docker` the container runs as `--user 1000:1000`. Use `--enable-docker` to mount the Docker socket.

## Testing

```bash
make test
```

See [tests/README.md](tests/README.md) for individual suites and options.

## Build

```bash
podman build -t claudainer:local .
```
