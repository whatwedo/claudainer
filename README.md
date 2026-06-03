# claude-code-container

Docker image that runs [Claude Code](https://claude.ai/code) as an isolated, per-project agent. Intended for use with [dde](https://github.com/whatwedo/dde) via `dde project:claude`, but works standalone too.

## What's inside

- `node:22-slim` base
- `node` user renamed to `developer` (UID 1000) with home at `/home/developer`
- Claude Code installed globally via npm
- `/workspace` as the working directory

## Build

```bash
docker build -t dde-claude:local .
```

## Usage with dde

Once built, `dde project:claude` (or `dde claude`) picks up the image automatically. See the [dde Claude Code guide](https://github.com/whatwedo/dde/blob/v2/docs/guides/claude-code.md) for full setup instructions.

## Standalone usage

```bash
docker run --rm -it \
  -u developer \
  -v ~/.claude:/home/developer/.claude \
  -v ~/.claude.json:/home/developer/.claude.json \
  -v "$(pwd)":/workspace \
  -e HOME=/home/developer \
  dde-claude:local \
  claude
```

Mount `~/.claude` and `~/.claude.json` from your host to share existing credentials and settings. Both files are written back on exit, so login is only required once.
