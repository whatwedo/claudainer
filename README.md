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
- Docker CLI installed

## Setup

Clone the repository, then source `source.sh` from your local clone:

```bash
git clone https://github.com/whatwedo/claudainer.git ~/git/whatwedo/claudainer.git
source ~/git/whatwedo/claudainer.git/source.sh
```

Any path works — `~/git/whatwedo/claudainer.git` is just an example.

To get the `claudainer` command in every shell, add the `source` line to your
`~/.bashrc` (or `~/.zshrc`):

```bash
echo 'source ~/git/whatwedo/claudainer.git/source.sh' >> ~/.bashrc
```

Keep it up to date with:

```bash
git -C ~/git/whatwedo/claudainer.git pull
```

`source.sh` is only ever loaded from your clone. Piping it in from a URL would
run whatever that endpoint serves at that moment, unreviewed, in every new
shell — cloning makes the code you execute reviewable and updated only when you
ask for it.

## Usage

```bash
claudainer [options] [claude args]
```

Run `claudainer` from any project directory. Your current directory is mounted **at the same absolute path** inside the container (e.g. `/Users/you/code/myapp` on the host is `/Users/you/code/myapp` in the container too), and that's also where the container's working directory is set. Claude credentials (`~/.claude` and `~/.claude.json`) are shared from your host so login is only required once.

Mirroring the host path (instead of a fixed `/workspace`) matters because Claude Code derives its session-storage folder under `~/.claude/projects/<slug>/` from the working directory — mirroring the real path means each project gets its own stable slug, identical to what a native (non-containerized) run would produce. That, in turn, is what lets host-side usage-tracking tools such as [CodeBurn](https://codeburn.app/) tell your projects apart. See [Usage tracking](#usage-tracking) below.

### Options

| Flag | Description |
|------|-------------|
| `--pull` | Pull the latest claudainer and proxy images before running |
| `--shell` | Start a bash shell instead of Claude Code |
| `--enable-git` | Mount `~/.gitconfig` and `~/.config/git/` (read-only) into the container |

### Examples

```bash
# Start Claude Code in the current directory
claudainer

# Pass arguments to claude
claudainer --dangerously-skip-permissions

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

Every path under `exclude_paths` is excluded from the project directory inside
the container so secrets it may contain are not exposed to the agent:

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
remove it from the list. The `.claudainer` file itself stays visible inside the
container; commit it or add it to `.gitignore` as you prefer.

`.claudainer` also accepts an optional `project` key — see
[Usage tracking](#usage-tracking) below.

## Usage tracking

Claude Code stores its session transcripts locally under
`~/.claude/projects/<slug>/`, where `<slug>` is derived from the working
directory a session ran in. Third-party dashboards such as
[CodeBurn](https://codeburn.app/) read those files directly to show token/cost
usage per project. Because `claudainer` mirrors your project's real host path
into the container (see [Usage](#usage) above) instead of always using a fixed
`/workspace`, each project gets its own stable slug — the same one a native,
non-containerized `claude` run in that directory would produce — so those
tools can tell your projects apart.

One case this doesn't cover on its own: if you check out one **git worktree
per branch/ticket** (each living in its own directory), path-mirroring alone
would give each worktree its own slug, fragmenting one logical project across
many. Pin a single stable identity instead with the `project` key in
`.claudainer`:

```yaml
project: whatwedo/claudainer
```

The project directory is then mounted (and the working directory set) at
`/home/developer/projects/whatwedo/claudainer` inside the container, so every
checkout produces the same slug. Because `.claudainer` is a regular file in
your repo, committing it means every worktree of that repo picks up the same
`project` automatically.

Note that neither Claude Code nor CodeBurn track a "ticket" concept — grouping
sessions by ticket (e.g. via the git branch each session ran on) would need a
separate script over the raw JSONL files and isn't part of this repo today.

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

The platform file detects the available container runtime, preferring `podman` over `docker`. With `podman` your user ID is mapped to UID 1000 inside the container via `--userns=keep-id`; with `docker` the container runs as `--user 1000:1000`.

Claude Code always runs behind a PTY filter that strips terminal mouse-tracking sequences from its output. This keeps plain mouse selection/copy working in terminals like macOS Terminal.app, at the cost of mouse interaction inside the TUI.

## Testing

```bash
make test
```

See [tests/README.md](tests/README.md) for individual suites and options.

## Build

```bash
podman build -t claudainer:local .
```
