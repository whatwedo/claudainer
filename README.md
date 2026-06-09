# Claudainer

Container image that runs [Claude Code](https://claude.ai/code) as an isolated, per-project agent.

## What's inside

- `debian:stable-slim` base
- user `developer` (UID 1000) with home at `/home/developer`
- Claude Code installed globally via npm
- Docker CLI installed (for `--docker-socket` flag support)
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
| `--pull` | Always pull the latest image before running |
| `--docker-socket`, `--ds` | Mount the Docker socket into the container |
| `--shell` | Start a bash shell instead of Claude Code |

### Examples

```bash
# Start Claude Code in the current directory
claudainer

# Pass arguments to claude
claudainer --dangerously-skip-permissions

# Mount Docker socket (e.g. for Docker-aware tasks)
claudainer --docker-socket

# Pull latest image and start
claudainer --pull

# Open a bash shell in the container (without starting Claude Code)
claudainer --shell
```

## How it works

`source.sh` detects your OS and sources the appropriate platform file:

The platform file detects the available container runtime, preferring `podman` over `docker`. With `podman` your user ID is mapped to UID 1000 inside the container via `--userns=keep-id`; with `docker` the container runs as `--user 1000:1000`. Use `--docker-socket` to mount the Docker socket.

## Build

```bash
podman build -t claudainer:local .
```
