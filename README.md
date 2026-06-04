# Claudainer

Container image that runs [Claude Code](https://claude.ai/code) as an isolated, per-project agent.

## What's inside

- `node:22-slim` base
- `node` user renamed to `developer` (UID 1000) with home at `/home/developer`
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
```

## How it works

`source.sh` detects your OS and sources the appropriate platform file:

Both platforms use `podman` and map your user ID to UID 1000 inside the container via `--userns=keep-id`. Use `--docker-socket` to mount the Docker socket.

## Build

```bash
podman build -t claudainer:local .
```
