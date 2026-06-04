# Claudainer

Container image that runs [Claude Code](https://claude.ai/code) as an isolated, per-project agent.

## What's inside

- `node:22-slim` base
- `node` user renamed to `developer` (UID 1000) with home at `/home/developer`
- Claude Code installed globally via npm
- Docker CLI installed (for `--docker` flag support)
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
| `--docker` | Mount the Docker socket into the container |

### Examples

```bash
# Start Claude Code in the current directory
claudainer

# Pass arguments to claude
claudainer --dangerously-skip-permissions

# Mount Docker socket (e.g. for Docker-aware tasks)
claudainer --docker

# Pull latest image and start
claudainer --pull
```

## How it works

`source.sh` detects your OS and sources the appropriate platform file:

- **Linux** — uses `podman`, maps your user ID to UID 1000 inside the container via `--userns=keep-id`. By default mounts the Podman socket; use `--docker` to mount the Docker socket instead.
- **macOS** — uses `docker`, runs as UID 1000 inside the container. Use `--docker` to mount the Docker socket.

## Build

```bash
docker build -t claudainer:local .
```
