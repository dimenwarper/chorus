# Idea Board + Agent Orchestrator — Service Specification

Status: Draft v1 (language-agnostic)

Purpose: Define a service that hosts a public idea board where community members suggest project ideas, a board owner curates and approves them, and an agent orchestrator dispatches coding agents to work on approved ideas.

## 1. Problem Statement

This service combines a public-facing idea board with an automated coding-agent orchestrator (derived from the [Symphony](https://github.com/openai/symphony) spec). It solves five operational problems:

- It gives a team or community a shared, visible place to propose and prioritize project ideas around a common theme (e.g., "exploring ML root problems").
- It lets community members show support for ideas via upvotes, giving the board owner signal on what resonates.
- It enforces a curation gate: only the board owner can promote community-suggested ideas into the active work queue.
- It turns approved ideas into a repeatable agent-dispatch workflow, isolating each idea in its own workspace and running a coding agent session against it.
- It keeps the workflow policy in-repo (`WORKFLOW.md`) so the board owner versions the agent prompt and runtime settings with their code.

Important boundaries:

- The idea board is the public-facing surface. The orchestrator is the execution engine behind it.
- Community members interact through the board (suggest, upvote, view status). They do not interact with the orchestrator directly.
- Ticket writes (state transitions, comments, PR links) in external trackers are performed by the coding agent, not the board service.

## 2. Goals and Non-Goals

### 2.1 Goals

- Host a public board with a configurable title and description that frames the purpose of the ideas.
- Allow authenticated (OAuth) users to submit new idea proposals.
- Allow anonymous users to upvote ideas (one vote per identity, enforced by fingerprint or session token).
- Provide a batch-review interface for the board owner to approve, reject, or request changes on pending ideas.
- Optionally weight dispatch priority by upvote count (configurable).
- Poll approved ideas on a fixed cadence and dispatch coding-agent work with bounded concurrency.
- Maintain a single authoritative orchestrator state for dispatch, retries, and reconciliation.
- Create deterministic per-idea workspaces and preserve them across runs.
- Stop active runs when idea state changes make them ineligible.
- Recover from transient failures with exponential backoff.
- Load runtime behavior from a repository-owned `WORKFLOW.md` contract.
- Expose operator-visible observability (structured logs at minimum).
- Support restart recovery without requiring a persistent database for orchestrator state.

### 2.2 Non-Goals

- General-purpose project management tool or full issue tracker replacement.
- Multi-tenant board hosting (one deployment = one board).
- Rich discussion threads or comment sections (may be added later).
- Built-in business logic for how to edit external tickets, PRs, or comments (that lives in the workflow prompt and agent tooling).
- Mandating strong sandbox controls beyond what the coding agent and host OS provide.
- Prescribing a specific dashboard or terminal UI implementation for the orchestrator layer.

## 3. System Overview

### 3.1 Main Components

1. **Board Service**
   - Serves the public-facing board UI.
   - Manages board metadata (title, description).
   - Handles OAuth authentication for idea submission.
   - Stores ideas, upvotes, and moderation state.
   - Exposes APIs for the admin review interface.

2. **Identity Layer**
   - OAuth provider integration for authenticated actions (idea submission).
   - Anonymous identity tracking for upvote deduplication (fingerprint, session token, or IP-based).

3. **Idea Store**
   - Persists ideas and their lifecycle state.
   - Persists upvote counts and voter identity mappings.
   - Provides query interfaces for the board UI, admin review, and orchestrator dispatch.

4. **Admin Review Interface**
   - Batch-oriented moderation surface for the board owner.
   - Allows approve, reject, or request-changes actions on pending ideas.
   - Allows manual priority assignment and tag management.

5. **Workflow Loader**
   - Reads `WORKFLOW.md`.
   - Parses YAML front matter and prompt body.
   - Returns `{config, prompt_template}`.

6. **Config Layer**
   - Exposes typed getters for workflow config values.
   - Applies defaults and environment variable indirection.
   - Performs validation used by the orchestrator before dispatch.

7. **Orchestrator**
   - Owns the poll tick.
   - Owns the in-memory runtime state.
   - Reads approved ideas from the Idea Store (instead of an external issue tracker).
   - Decides which ideas to dispatch, retry, stop, or release.
   - Tracks session metrics and retry queue state.

8. **Workspace Manager**
   - Maps idea identifiers to workspace paths.
   - Ensures per-idea workspace directories exist.
   - Runs workspace lifecycle hooks.
   - Cleans workspaces for terminal ideas.

9. **Agent Runner**
   - Creates workspace.
   - Builds prompt from idea + workflow template.
   - Launches the coding agent app-server client.
   - Streams agent updates back to the orchestrator.

10. **Status Surface** (optional)
    - Presents human-readable runtime status for the board owner/operator.

11. **Logging**
    - Emits structured runtime logs to one or more configured sinks.

### 3.2 Abstraction Layers

1. **Presentation Layer** (public board + admin review)
   - Board UI: title, description, idea list, upvotes, submission form.
   - Admin UI: batch review queue, priority management, board settings.

2. **Identity & Access Layer** (OAuth + anonymous tracking)
   - Authenticated users: submit ideas.
   - Anonymous visitors: view board, upvote (once per identity per idea).
   - Board owner: approve/reject, configure board, view orchestrator status.

3. **Data Layer** (idea store)
   - Ideas, upvotes, moderation decisions, board metadata.

4. **Policy Layer** (repo-defined)
   - `WORKFLOW.md` prompt body.
   - Team-specific rules for idea handling, validation, and handoff.

5. **Configuration Layer** (typed getters)
   - Parses front matter into typed runtime settings.
   - Handles defaults, environment tokens, and path normalization.

6. **Coordination Layer** (orchestrator)
   - Polling loop, idea eligibility, concurrency, retries, reconciliation.

7. **Execution Layer** (workspace + agent subprocess)
   - Filesystem lifecycle, workspace preparation, coding-agent protocol.

8. **Observability Layer** (logs + optional status surface)
   - Operator visibility into orchestrator and agent behavior.

### 3.3 External Dependencies

- OAuth provider(s) (e.g., GitHub, Google) for authenticated idea submission.
- Persistent storage backend for the Idea Store (database, file-backed store, or hosted service).
- Local filesystem for workspaces and logs.
- Optional workspace population tooling (e.g., Git CLI).
- Coding-agent executable that supports JSON-RPC-like app-server mode over stdio.
- Host environment authentication for the coding agent.
- Optional external issue tracker (Linear, etc.) if the workflow prompt directs the agent to sync work there.

## 4. Core Domain Model

### 4.1 Entities

#### 4.1.1 Board

Top-level configuration for the public-facing board.

Fields:

- `id` (string) — Unique board identifier.
- `title` (string) — Display title (e.g., "ML Root Problems").
- `description` (string) — Markdown-formatted description explaining the board's purpose and what kinds of ideas are welcome.
- `owner_id` (string) — OAuth identity of the board owner/admin.
- `created_at` (timestamp)
- `updated_at` (timestamp)
- `settings` (BoardSettings object)

#### 4.1.2 Board Settings

Configurable behavior for the board.

Fields:

- `upvote_weight_enabled` (boolean, default: `false`) — When true, upvote count is factored into dispatch priority.
- `upvote_weight_factor` (float, default: `1.0`) — Multiplier applied to upvote count when computing dispatch score. Only meaningful when `upvote_weight_enabled` is true.
- `require_oauth_to_upvote` (boolean, default: `false`) — When true, upvoting requires OAuth login. When false, anonymous upvoting is permitted with deduplication.
- `anonymous_upvote_strategy` (enum: `fingerprint`, `session_token`, `ip`, default: `fingerprint`) — Method used to deduplicate anonymous upvotes.
- `allowed_oauth_providers` (list of strings, default: `["github"]`) — Which OAuth providers are accepted for idea submission.
- `max_pending_ideas_per_user` (integer, default: `10`) — Rate limit on pending (unreviewed) ideas per authenticated user.

#### 4.1.3 Idea

A project idea proposed by a community member or the board owner.

Fields:

- `id` (string) — Stable internal ID (UUID or similar).
- `identifier` (string) — Human-readable short key (e.g., `IDEA-042`). Auto-generated, sequential.
- `title` (string) — Short summary of the idea.
- `description` (string or null) — Longer Markdown-formatted explanation.
- `submitted_by` (SubmitterIdentity object)
- `status` (IdeaStatus enum)
- `priority` (integer or null) — Manually set by board owner. Lower = higher priority. Null = unset.
- `upvote_count` (integer, default: 0)
- `tags` (list of strings) — Freeform labels applied by board owner or submitter.
- `admin_notes` (string or null) — Private notes from board owner (not shown publicly).
- `rejection_reason` (string or null) — Shown to submitter if rejected.
- `created_at` (timestamp)
- `updated_at` (timestamp)
- `approved_at` (timestamp or null)
- `resolved_at` (timestamp or null)

#### 4.1.4 Idea Status (Enum)

Lifecycle states for an idea:

- `pending` — Submitted, awaiting board owner review. Visible on board but marked as pending.
- `approved` — Board owner has approved. Eligible for orchestrator dispatch.
- `in_progress` — Orchestrator has dispatched or is actively working the idea.
- `completed` — Agent work finished successfully (or board owner marked complete).
- `rejected` — Board owner declined the idea. Optionally visible with rejection reason.
- `archived` — Removed from active view. Not eligible for dispatch.

State transition rules:

- `pending` → `approved` | `rejected` (board owner action)
- `approved` → `in_progress` (orchestrator dispatch) | `archived` (board owner)
- `in_progress` → `completed` | `approved` (orchestrator releases back) | `archived` (board owner)
- `completed` → `archived` (board owner)
- `rejected` → `pending` (board owner reconsiders) | `archived`

#### 4.1.5 Submitter Identity

Fields:

- `user_id` (string) — OAuth provider user ID.
- `provider` (string) — OAuth provider name (e.g., `github`, `google`).
- `display_name` (string) — Public display name.
- `avatar_url` (string or null)

#### 4.1.6 Upvote

Fields:

- `idea_id` (string)
- `voter_identity` (string) — For authenticated users: `oauth:<provider>:<user_id>`. For anonymous: `anon:<fingerprint|session|ip>`.
- `created_at` (timestamp)

Constraints:

- Unique on `(idea_id, voter_identity)`. Duplicate upvote attempts are idempotent (no error, no second count).
- Upvotes are permitted on ideas in any visible status (`pending`, `approved`, `in_progress`, `completed`). Not permitted on `rejected` or `archived`.

#### 4.1.7 Workflow Definition

Parsed `WORKFLOW.md` payload:

- `config` (map) — YAML front matter root object.
- `prompt_template` (string) — Markdown body after front matter, trimmed.

#### 4.1.8 Service Config (Typed View)

Typed runtime values derived from `WorkflowDefinition.config` plus environment resolution. See Section 6 for full schema.

#### 4.1.9 Workspace

Filesystem workspace assigned to one idea identifier.

Fields (logical):

- `path` (workspace path)
- `workspace_key` (sanitized idea identifier)
- `created_now` (boolean, used to gate `after_create` hook)

#### 4.1.10 Run Attempt

One execution attempt for one idea.

Fields (logical):

- `idea_id`
- `idea_identifier`
- `attempt` (integer or null — `null` for first run, `>=1` for retries/continuation)
- `workspace_path`
- `started_at`
- `status`
- `error` (optional)

#### 4.1.11 Live Session (Agent Session Metadata)

State tracked while a coding-agent subprocess is running. Identical to Symphony spec Section 4.1.6.

Fields:

- `session_id` (string, `<thread_id>-<turn_id>`)
- `thread_id` (string)
- `turn_id` (string)
- `codex_app_server_pid` (string or null)
- `last_codex_event` (string/enum or null)
- `last_codex_timestamp` (timestamp or null)
- `last_codex_message` (summarized payload)
- `codex_input_tokens` / `codex_output_tokens` / `codex_total_tokens` (integers)
- `last_reported_input_tokens` / `last_reported_output_tokens` / `last_reported_total_tokens` (integers)
- `turn_count` (integer)

#### 4.1.12 Retry Entry

Scheduled retry state for an idea. Identical in structure to Symphony spec Section 4.1.7, keyed by `idea_id` instead of `issue_id`.

#### 4.1.13 Orchestrator Runtime State

Single authoritative in-memory state owned by the orchestrator.

Fields:

- `poll_interval_ms`
- `max_concurrent_agents`
- `running` (map `idea_id -> running entry`)
- `claimed` (set of idea IDs)
- `retry_attempts` (map `idea_id -> RetryEntry`)
- `completed` (set of idea IDs; bookkeeping only)
- `codex_totals` (aggregate tokens + runtime seconds)
- `codex_rate_limits` (latest rate-limit snapshot)

### 4.2 Stable Identifiers and Normalization Rules

- **Idea ID**: Use for internal map keys and store lookups.
- **Idea Identifier**: Use for human-readable display and workspace naming. Format: `IDEA-<sequential_number>` (zero-padded optional).
- **Workspace Key**: Derive from `idea.identifier` by replacing any character not in `[A-Za-z0-9._-]` with `_`.
- **Normalized Idea Status**: Compare after `trim` + `lowercase`.
- **Session ID**: Compose as `<thread_id>-<turn_id>`.

## 5. Board Service Specification

### 5.1 Public Board Endpoints

The board service exposes a public-facing UI and corresponding API.

#### 5.1.1 Board View (`GET /`)

Displays:

- Board title and description (Markdown rendered).
- List of visible ideas grouped or sorted by status and popularity.
- Each idea shows: identifier, title, status badge, upvote count with vote button, submitter display name, tags, and timestamps.
- Ideas in `rejected` status are hidden by default (configurable).
- Ideas in `archived` status are never shown.

Default sort order for visible ideas:

1. Status group priority: `in_progress` first, then `approved`, then `completed`, then `pending`.
2. Within each group: upvote count descending, then `created_at` oldest first.

#### 5.1.2 Idea Detail View (`GET /ideas/:identifier`)

Displays:

- Full idea title and description.
- Current status with visual indicator.
- Upvote count and vote button.
- Submitter identity (display name + avatar).
- Tags.
- If `in_progress` or `completed`: summary of agent work status (from orchestrator, if available).

#### 5.1.3 Idea Submission (`POST /api/ideas`)

Requires: Valid OAuth session.

Request body:

- `title` (string, required, 5–200 characters)
- `description` (string, optional, max 10,000 characters, Markdown)
- `tags` (list of strings, optional, max 5 tags, each max 30 characters)

Validation:

- Authenticated user must not exceed `max_pending_ideas_per_user` pending ideas.
- Title must be non-empty after trimming.
- Duplicate detection is not required but implementations may optionally flag similar titles.

Response: Created idea object with `status: pending`.

#### 5.1.4 Upvote (`POST /api/ideas/:id/upvote`)

Accepts both authenticated and anonymous requests (unless `require_oauth_to_upvote` is true).

Identity resolution:

- Authenticated: `oauth:<provider>:<user_id>`
- Anonymous: `anon:<strategy_value>` based on `anonymous_upvote_strategy`

Behavior:

- If voter has not upvoted this idea: create upvote, increment count, return `{upvoted: true, count: N}`.
- If voter has already upvoted: no-op, return `{upvoted: true, count: N}` (idempotent).

#### 5.1.5 Remove Upvote (`DELETE /api/ideas/:id/upvote`)

Same identity resolution as upvote.

Behavior:

- If voter has upvoted: remove upvote, decrement count, return `{upvoted: false, count: N}`.
- If voter has not upvoted: no-op, return `{upvoted: false, count: N}`.

### 5.2 Admin Endpoints

All admin endpoints require board owner authentication.

#### 5.2.1 Review Queue (`GET /admin/review`)

Returns all ideas in `pending` status, sorted by `created_at` ascending (oldest first).

Each item shows: identifier, title, description preview, submitter identity, upvote count, tags, submitted timestamp.

#### 5.2.2 Batch Review (`POST /admin/review/batch`)

Request body:

```json
{
  "actions": [
    {"idea_id": "...", "action": "approve"},
    {"idea_id": "...", "action": "approve", "priority": 2, "tags": ["infra"]},
    {"idea_id": "...", "action": "reject", "reason": "Out of scope for this board."},
    {"idea_id": "...", "action": "reject"}
  ]
}
```

Actions:

- `approve` — Transitions idea to `approved`. Optionally sets `priority` and/or `tags`.
- `reject` — Transitions idea to `rejected`. Optionally sets `rejection_reason`.

Validation:

- All referenced ideas must be in `pending` status. Non-pending ideas in the batch are skipped with an error entry in the response.

Response: List of results per action (success or error with reason).

#### 5.2.3 Idea Management (`PATCH /admin/ideas/:id`)

Allows the board owner to update any idea field:

- `priority` (integer or null)
- `tags` (list of strings)
- `status` (must follow valid state transitions from Section 4.1.4)
- `admin_notes` (string)
- `title`, `description` (editorial override)

#### 5.2.4 Board Settings (`GET/PATCH /admin/settings`)

Read or update `BoardSettings` fields (Section 4.1.2).

### 5.3 OAuth Flow

The board service must support at least one OAuth 2.0 provider for authenticated identity.

Required flow:

1. User clicks "Sign in" on the board.
2. Redirect to OAuth provider authorization endpoint.
3. Provider redirects back with authorization code.
4. Board service exchanges code for access token.
5. Board service fetches user profile (ID, display name, avatar).
6. Board service creates or updates a session for the user.

Session management:

- Sessions are stored server-side or as signed tokens (JWT or similar).
- Session expiry is implementation-defined but should be at least 24 hours.
- The board service does not store OAuth access tokens beyond the initial profile fetch unless needed for ongoing provider API access.

## 6. Workflow Specification (Repository Contract)

The workflow contract is substantially the same as Symphony. Key differences are noted.

### 6.1 File Discovery and Path Resolution

Identical to Symphony Section 5.1. Workflow file path precedence: explicit runtime setting, then `WORKFLOW.md` in cwd.

### 6.2 File Format

Identical to Symphony Section 5.2. YAML front matter + Markdown prompt body.

### 6.3 Front Matter Schema

Top-level keys:

- `board` (new — board-specific config, see 6.3.1)
- `tracker` (optional — external tracker integration, if the agent should sync to Linear or similar)
- `polling`
- `workspace`
- `hooks`
- `agent`
- `codex`
- `server` (optional extension)

Unknown keys are ignored for forward compatibility.

#### 6.3.1 `board` (object) — NEW

Fields:

- `title` (string) — Board display title. Can also be set via Board Settings API; WORKFLOW.md is the default/seed value.
- `description` (string) — Board description (Markdown). Same override semantics as title.
- `upvote_weight_enabled` (boolean, default: `false`)
- `upvote_weight_factor` (float, default: `1.0`)
- `dispatch_priority_mode` (enum: `manual`, `upvotes`, `hybrid`, default: `manual`)
  - `manual`: Dispatch priority is determined solely by the `priority` field set by the board owner.
  - `upvotes`: Dispatch priority is determined by upvote count (descending).
  - `hybrid`: Dispatch priority uses a composite score combining manual priority and upvote count. Formula: `score = (priority_rank * priority_weight) + (upvote_rank * upvote_weight)`. Lower score = higher dispatch priority.
- `priority_weight` (float, default: `0.7`) — Weight for manual priority in hybrid mode.
- `upvote_weight` (float, default: `0.3`) — Weight for upvote rank in hybrid mode.

#### 6.3.2 `tracker` (object) — OPTIONAL

Identical to Symphony Section 5.3.1. If present, the agent can sync work to an external tracker. If absent, the board's own Idea Store is the sole source of truth for idea state.

When `tracker` is configured:

- The orchestrator still reads dispatch candidates from the Idea Store (not the external tracker).
- The workflow prompt may instruct the agent to create/update external tracker issues as part of its work.
- Reconciliation checks the Idea Store, not the external tracker.

#### 6.3.3–6.3.6

`polling`, `workspace`, `hooks`, `agent`, `codex` — Identical to Symphony Sections 5.3.2–5.3.6.

### 6.4 Prompt Template Contract

The Markdown body of `WORKFLOW.md` is the per-idea prompt template.

Template input variables:

- `idea` (object) — All Idea fields from Section 4.1.3 (replaces `issue`).
- `attempt` (integer or null)
- `board` (object) — Board title and description, for context.

Rendering rules are identical to Symphony Section 5.4.

### 6.5 Workflow Validation and Error Surface

Identical to Symphony Section 5.5.

## 7. Orchestration State Machine

The orchestrator is structurally similar to Symphony, with the Idea Store replacing the external issue tracker as the source of dispatch candidates.

### 7.1 Idea Orchestration States

Internal claim states (not the same as `IdeaStatus`):

1. `Unclaimed` — Idea is not running and has no retry scheduled.
2. `Claimed` — Orchestrator has reserved the idea.
3. `Running` — Worker task exists.
4. `RetryQueued` — Worker is not running, but a retry timer exists.
5. `Released` — Claim removed.

### 7.2 Run Attempt Lifecycle

Identical to Symphony Section 7.2.

### 7.3 Transition Triggers

Identical to Symphony Section 7.3, with "issue" replaced by "idea" and the Idea Store replacing the tracker client.

Additional trigger:

- **Admin Status Change**: If the board owner changes an idea's status (e.g., archives an in-progress idea), reconciliation detects this and stops the active run.

### 7.4 Idempotency and Recovery Rules

Identical to Symphony Section 7.4.

## 8. Polling, Scheduling, and Reconciliation

### 8.1 Poll Loop

Identical to Symphony Section 8.1, except the candidate source is the Idea Store rather than an external tracker.

Tick sequence:

1. Reconcile running ideas.
2. Run dispatch preflight validation.
3. Fetch candidate ideas from Idea Store (status = `approved` or `in_progress`).
4. Sort ideas by dispatch priority.
5. Dispatch eligible ideas while slots remain.
6. Update idea statuses (`approved` → `in_progress` on dispatch).
7. Notify observability/status consumers.

### 8.2 Candidate Selection Rules

An idea is dispatch-eligible only if all are true:

- It has `id`, `identifier`, `title`, and `status`.
- Its status is `approved` (for new dispatch) or `in_progress` (for continuation).
- It is not already in `running`.
- It is not already in `claimed`.
- Global concurrency slots are available.

Sorting order depends on `board.dispatch_priority_mode`:

**`manual` mode:**

1. `priority` ascending (lower = higher priority; null sorts last).
2. `approved_at` oldest first.
3. `identifier` lexicographic tie-breaker.

**`upvotes` mode:**

1. `upvote_count` descending.
2. `approved_at` oldest first.
3. `identifier` tie-breaker.

**`hybrid` mode:**

1. Composite score ascending (see formula in Section 6.3.1).
2. `approved_at` oldest first.
3. `identifier` tie-breaker.

### 8.3 Concurrency Control

Identical to Symphony Section 8.3.

### 8.4 Retry and Backoff

Identical to Symphony Section 8.4.

### 8.5 Active Run Reconciliation

Two parts, adapted from Symphony:

**Part A: Stall detection** — Identical to Symphony.

**Part B: Idea status refresh**

- For each running idea, re-read its status from the Idea Store.
- If status is terminal (`completed`, `archived`): terminate worker and clean workspace.
- If status is still active (`approved`, `in_progress`): update in-memory snapshot.
- If status is `rejected` or `pending`: terminate worker without workspace cleanup.

### 8.6 Startup Workspace Cleanup

On startup, query the Idea Store for ideas in terminal statuses (`completed`, `archived`). Remove corresponding workspace directories.

## 9. Workspace Management and Safety

Identical to Symphony Section 9, with "issue" replaced by "idea" throughout. All safety invariants (root containment, key sanitization, cwd validation) apply unchanged.

## 10. Agent Runner Protocol (Coding Agent Integration)

Identical to Symphony Section 10. The only change is that the prompt template receives an `idea` object instead of an `issue` object, and the turn title format is `<idea.identifier>: <idea.title>`.

## 11. Idea Store Contract

The Idea Store replaces the external issue tracker as the primary data source for the orchestrator. It also serves the board UI and admin interface.

### 11.1 Required Operations

1. `fetch_candidate_ideas()` — Return ideas with status `approved` or `in_progress`.
2. `fetch_ideas_by_statuses(statuses)` — Used for startup cleanup and admin queries.
3. `fetch_idea_statuses_by_ids(idea_ids)` — Used for active-run reconciliation.
4. `create_idea(idea)` — Insert a new idea (from submission endpoint).
5. `update_idea(idea_id, changes)` — Update idea fields (from admin actions, orchestrator status transitions).
6. `create_upvote(idea_id, voter_identity)` — Idempotent upvote creation.
7. `delete_upvote(idea_id, voter_identity)` — Upvote removal.
8. `get_upvote_count(idea_id)` — Current count.
9. `has_upvoted(idea_id, voter_identity)` — Check for UI state.

### 11.2 Storage Backend

The spec does not prescribe a specific storage backend. Conforming options include:

- Relational database (PostgreSQL, SQLite, etc.)
- Document store (MongoDB, etc.)
- File-backed JSON/YAML store (for simple single-operator deployments)
- Hosted service with API (Supabase, Firebase, etc.)

Requirements:

- ACID-like guarantees for upvote deduplication (unique constraint on `(idea_id, voter_identity)`).
- Efficient query by status for dispatch candidate fetching.
- Support for batch reads and writes for admin review.

### 11.3 External Tracker Sync (Optional)

If `tracker` is configured in `WORKFLOW.md`:

- The orchestrator does NOT read from the external tracker for dispatch decisions.
- The workflow prompt may instruct the agent to create/update issues in the external tracker.
- An optional sync hook (`hooks.after_run`) can reconcile Idea Store status with external tracker state.

## 12. Prompt Construction and Context Assembly

### 12.1 Inputs

- `workflow.prompt_template`
- Normalized `idea` object (all fields from Section 4.1.3)
- `attempt` (integer or null)
- `board` (object with `title` and `description`)

### 12.2 Rendering Rules

Identical to Symphony Section 12.2.

### 12.3 Retry/Continuation Semantics

Identical to Symphony Section 12.3.

### 12.4 Failure Semantics

Identical to Symphony Section 12.4.

## 13. Logging, Status, and Observability

Identical to Symphony Section 13, with the following additions:

### 13.1 Board-Specific Logging

Required additional log events:

- Idea submitted (with `idea_id`, `submitted_by`).
- Idea approved/rejected (with `idea_id`, batch context if applicable).
- Upvote created/removed (with `idea_id`, anonymized voter identity).

### 13.2 Public Board Status

The public board UI should display, for ideas in `in_progress` status:

- A general activity indicator ("Agent is working on this").
- Optionally: last agent event summary (e.g., "Running tests", "Creating PR") derived from orchestrator state.
- Detailed agent telemetry (tokens, session IDs, etc.) is only shown in the admin/operator view, not publicly.

### 13.3 Admin Dashboard

The admin interface should include:

- Pending review queue count badge.
- Running agent session summary (from orchestrator snapshot).
- Retry queue visibility.
- Aggregate token consumption.

### 13.4 Optional HTTP API

If an HTTP server is implemented (per Symphony Section 13.7), the following additional endpoints are recommended:

- `GET /api/v1/board` — Board metadata and aggregate stats (total ideas, breakdown by status, total upvotes).
- `GET /api/v1/ideas` — Paginated list of visible ideas with upvote counts and status.
- `GET /api/v1/ideas/:identifier` — Full idea detail with agent status if in-progress.

## 14. Failure Model and Recovery Strategy

Identical to Symphony Section 14, with the following additions:

### 14.1 Additional Failure Classes

6. **Board Service Failures**
   - OAuth provider unavailable.
   - Idea Store write failures (submission, upvote).
   - Admin batch review partially fails (some actions succeed, others fail).

7. **Identity Failures**
   - Anonymous fingerprint collision (acceptable; upvote dedup is best-effort for anonymous users).
   - OAuth token refresh failure.

### 14.2 Board-Specific Recovery

- OAuth provider unavailable: Show error on login/submit, allow anonymous browsing and upvoting to continue.
- Idea Store write failure on upvote: Return error to client, do not increment count. Client may retry.
- Partial batch review failure: Return per-action results. Successful actions are committed. Failed actions include error details.

## 15. Security and Operational Safety

Inherits all of Symphony Section 15, plus:

### 15.1 Board-Specific Security

- **Input sanitization**: All user-submitted content (titles, descriptions, tags) must be sanitized before rendering. Markdown rendering must prevent XSS.
- **Rate limiting**: Idea submission and upvote endpoints should be rate-limited per identity and globally.
- **OAuth state validation**: CSRF protection via `state` parameter in OAuth flow.
- **Admin authentication**: Board owner identity must be validated on all admin endpoints. Implementation may use the same OAuth flow with role checks or a separate admin auth mechanism.
- **Anonymous upvote abuse**: Fingerprint-based dedup is best-effort. Implementations should monitor for unusual voting patterns and may implement additional protections (CAPTCHA, progressive rate limiting).

### 15.2 Public Data Considerations

- Idea titles, descriptions, tags, submitter display names, and upvote counts are public.
- Submitter email addresses are never exposed publicly.
- Admin notes and internal orchestrator details (session IDs, token counts, workspace paths) are never exposed publicly.
- Voter identities (including anonymous fingerprints) are never exposed publicly.

## 16. Configuration Specification

Identical to Symphony Section 6 for orchestrator-related config. Board-specific configuration is managed through:

1. `WORKFLOW.md` front matter `board` section (seed values, dispatch priority config).
2. Board Settings API (`/admin/settings`) for runtime board behavior.
3. Environment variables for secrets (OAuth client ID/secret, database connection strings).

Precedence for board metadata (title, description):

1. Board Settings API (if board owner has explicitly updated).
2. `WORKFLOW.md` `board.title` / `board.description` (seed/default).

## 17. Test and Validation Matrix

Inherits all of Symphony Section 17, plus:

### 17.1 Board Service Tests (Core Conformance)

- Board title and description render correctly from config and API overrides.
- Idea submission requires valid OAuth session.
- Idea submission enforces `max_pending_ideas_per_user`.
- Upvote is idempotent (same identity, same idea = no duplicate).
- Upvote removal works and decrements count.
- Anonymous upvote deduplication prevents double-counting from same identity.
- Upvotes on `rejected` or `archived` ideas are rejected.
- Batch review transitions only `pending` ideas, skips non-pending with error.
- Admin settings update persists and takes effect.

### 17.2 Dispatch Priority Tests (Core Conformance)

- `manual` mode sorts by `priority` ascending, then `approved_at`.
- `upvotes` mode sorts by `upvote_count` descending, then `approved_at`.
- `hybrid` mode produces correct composite scores.
- Changing `dispatch_priority_mode` at runtime affects next dispatch cycle.

### 17.3 Integration Tests (Core Conformance)

- Idea submitted → approved → dispatched → in_progress status update visible on board.
- Idea archived while in_progress → agent run terminated.
- Upvote count visible and correct on board UI.
- OAuth login flow completes and session is established.

## 18. Implementation Checklist (Definition of Done)

### 18.1 Required for Conformance

Everything from Symphony Section 18.1 (with "issue" → "idea"), plus:

- Board service with title, description, and idea listing.
- OAuth integration for at least one provider.
- Idea submission with validation and rate limiting.
- Upvote/remove-upvote with deduplication.
- Batch review interface for board owner.
- Idea Store with required operations.
- Configurable dispatch priority modes (`manual`, `upvotes`, `hybrid`).
- Orchestrator reads from Idea Store instead of external tracker.
- Public board displays agent activity status for in-progress ideas.
- Input sanitization and XSS prevention.
- Admin authentication on all admin endpoints.

### 18.2 Recommended Extensions

Everything from Symphony Section 18.2, plus:

- TODO: Rich idea discussions / comment threads.
- TODO: Webhook notifications when ideas change status.
- TODO: Email digest of new pending ideas for board owner.
- TODO: Multiple board support (multi-tenant).
- TODO: Idea templates (structured submission forms per board).
- TODO: Public API for third-party integrations.
- TODO: Upvote analytics and trend visualization.
