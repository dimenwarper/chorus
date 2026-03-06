# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Chorus is an idea board + agent orchestrator service built with Elixir/Phoenix. Community members suggest project ideas, a board owner curates them, and an orchestrator dispatches coding agents to work on approved ideas. See `SPEC.md` for the full specification.

## Stack

- Elixir 1.19+ / OTP 28 / Phoenix 1.8 / Phoenix LiveView 1.1
- SQLite via Ecto + ecto_sqlite3 (database files: `chorus_dev.db`, `chorus_test.db`)
- Bandit HTTP server
- Tailwind CSS + esbuild for assets

## Commands

```bash
mix setup              # Install deps, create DB, migrate, build assets
mix phx.server         # Start dev server (localhost:4000)
iex -S mix phx.server  # Start with interactive shell
mix test               # Run all tests
mix test path/to/test.exs          # Run single test file
mix test path/to/test.exs:42       # Run single test at line
mix ecto.migrate       # Run pending migrations
mix ecto.gen.migration name        # Generate a new migration
mix format             # Format all code
mix precommit          # Compile (warnings-as-errors) + format + test
```

## Architecture

Two main OTP application trees:

- `Chorus` — Business logic, Ecto schemas, Idea Store, orchestrator (GenServer)
- `ChorusWeb` — Phoenix endpoint, router, controllers, LiveView components

Key directories:
- `lib/chorus/` — Domain layer (schemas, contexts, orchestrator, workspace manager, agent runner)
- `lib/chorus_web/` — Web layer (router, controllers, live views, components)
- `priv/repo/migrations/` — Ecto migrations
- `config/` — Environment-specific config (`dev.exs`, `test.exs`, `runtime.exs`)

## Conventions

- Phoenix contexts pattern: group related functionality in context modules under `lib/chorus/`
- Ecto changesets for all data validation
- LiveView for real-time UI updates (board view, admin dashboard)
- `WORKFLOW.md` in the repo root defines the agent prompt template and orchestrator config (YAML front matter + Markdown body)
