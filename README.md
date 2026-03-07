# Chorus

> **This is a reference implementation.** The canonical definition of Chorus lives in [`SPEC.md`](SPEC.md), which is implementation-agnostic. If you're building your own version, start from the spec — a from-scratch implementation in your preferred stack is encouraged over forking this repo.

An idea board + coding agent orchestrator. Community members propose project ideas, a board owner curates them, and an orchestrator dispatches coding agents to work on approved ideas — each in its own git repo with per-task branches.

## How It Works

1. **Community submits ideas** — Authenticated users (via GitHub OAuth) propose project ideas on a public board.
2. **Board owner curates** — The admin reviews, approves, or rejects ideas. Approval creates a GitHub repo and clones it locally.
3. **Tasks are created** — The board owner breaks approved ideas into discrete tasks.
4. **Agents execute** — The orchestrator polls for pending tasks and dispatches coding agents (e.g., Claude Code) to work on them in parallel, each on its own branch.
5. **Progress is visible** — A live activity feed shows what agents are working on in real time.

## Features

- **Public idea board** with upvoting, live activity feed, and real-time updates via LiveView
- **Idea moderation** — pending ideas are hidden from the public board until approved
- **GitHub integration** — repos created automatically on idea approval; existing repos can be onboarded
- **Admin dashboard** — kanban board for tasks, idea management with editable repo URLs, review queue, board settings
- **Agent orchestrator** — configurable polling, bounded concurrency, retry with exponential backoff, restart recovery
- **Workflow-as-code** — agent prompt and runtime config live in `WORKFLOW.md` (YAML front matter + Markdown body)
- **Per-idea repos, per-task branches** — clean git isolation for parallel agent work

## Stack

- Elixir / OTP / Phoenix / Phoenix LiveView
- SQLite via Ecto (ecto_sqlite3)
- Tailwind CSS + DaisyUI
- GitHub OAuth (Ueberauth)
- GitHub API for repo creation

## Setup

```bash
mix setup   # install deps, create DB, migrate, build assets
```

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `GITHUB_CLIENT_ID` | For auth | GitHub OAuth app client ID |
| `GITHUB_CLIENT_SECRET` | For auth | GitHub OAuth app client secret |
| `ADMIN_GITHUB_ID` | Recommended | Numeric GitHub user ID of the board owner |
| `GITHUB_TOKEN` | For repo creation | GitHub personal access token with `repo` scope |
| `GITHUB_OWNER` | For repo creation | GitHub username or org for new repos |
| `DATABASE_PATH` | Production | Path to SQLite database file |
| `SECRET_KEY_BASE` | Production | Phoenix secret (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | Production | Public hostname |
| `PHX_SERVER` | Production | Set to `true` to start the HTTP server |
| `PORT` | Optional | HTTP port (default: 4000) |

In development, if `GITHUB_CLIENT_ID` is not set, a dev auto-login is used.

### Running

```bash
mix phx.server              # start dev server at localhost:4000
iex -S mix phx.server       # start with interactive shell
```

### WORKFLOW.md

Create a `WORKFLOW.md` in the project root to configure the orchestrator. YAML front matter defines runtime settings, and the Markdown body is the prompt template sent to coding agents.

```markdown
---
workspace_root: .chorus/workspaces
agent_command: claude -p --verbose
max_concurrent: 3
poll_interval_ms: 30000
max_retries: 2
---

You are working on {{idea.title}}.

## Instructions
...
```

## Deploying to a VPS

There's a setup script that installs everything on a fresh Ubuntu/Debian server:

```bash
sudo bash deploy/setup.sh
```

This installs Erlang/Elixir (via asdf), Caddy (reverse proxy with auto HTTPS), builds a production release, creates a systemd service, and generates the config template at `/etc/chorus/env`.

After setup, edit `/etc/chorus/env` with your values, configure Caddy with your domain, and start the service:

```bash
sudo systemctl start chorus
```

See `deploy/` for the systemd service file, Caddy config example, and env template.

## Development

```bash
mix test                          # run all tests
mix test path/to/test.exs         # run single test file
mix test path/to/test.exs:42      # run test at line
mix format                        # format code
mix precommit                     # compile (warnings-as-errors) + format + test
```

## Architecture

Two main OTP application trees:

- **Chorus** — domain layer: Ecto schemas, Idea Store, Task Store, orchestrator (GenServer), workspace manager, agent runner
- **ChorusWeb** — web layer: Phoenix endpoint, router, controllers, LiveView pages and components

The orchestrator runs as a GenServer that polls for pending tasks, manages agent subprocesses via Erlang ports, and broadcasts activity events over Phoenix PubSub for the live feed.

See [SPEC.md](SPEC.md) for the full service specification.

## License

Copyright (c) 2026. All rights reserved.
