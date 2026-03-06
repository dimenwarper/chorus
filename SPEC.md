# Idea Board + Agent Orchestrator — Service Specification

Status: Draft v2 (language-agnostic)

Purpose: Define a service that hosts a public idea board where community members suggest project ideas, a board owner curates and approves them, and an agent orchestrator dispatches coding agents to work on tasks within approved ideas.

## 1. Problem Statement

This service combines a public-facing idea board with an automated coding-agent orchestrator (derived from the [Symphony](https://github.com/openai/symphony) spec). It solves five operational problems:

- It gives a team or community a shared, visible place to propose and prioritize project ideas around a common theme (e.g., "exploring ML root problems").
- It lets community members show support for ideas via upvotes, giving the board owner signal on what resonates.
- It enforces a curation gate: only the board owner can promote community-suggested ideas into the active work queue.
- It turns approved ideas into repositories of work, where the board owner breaks ideas into discrete tasks that are dispatched to coding agents in parallel.
- It keeps the workflow policy in-repo (`WORKFLOW.md`) so the board owner versions the agent prompt and runtime settings with their code.

Important boundaries:

- The idea board is the public-facing surface. The orchestrator is the execution engine behind it.
- Community members interact through the board (suggest, upvote, view status). They do not interact with the orchestrator directly.
- Ideas are containers for work. Tasks are the atomic units of dispatch.
- Ticket writes (state transitions, comments, PR links) in external trackers are performed by the coding agent, not the board service.

## 2. Goals and Non-Goals

### 2.1 Goals

- Host a public board with a configurable title and description that frames the purpose of the ideas.
- Allow authenticated (OAuth) users to submit new idea proposals.
- Allow anonymous users to upvote ideas (one vote per identity, enforced by fingerprint or session token).
- Provide a batch-review interface for the board owner to approve, reject, or request changes on pending ideas.
- Allow the board owner to break approved ideas into multiple tasks, each dispatched independently.
- Support parallel task execution within the same idea, each on its own git branch.
- Optionally weight dispatch priority by upvote count (configurable).
- Poll pending tasks on a fixed cadence and dispatch coding-agent work with bounded concurrency.
- Maintain a single authoritative orchestrator state for dispatch, retries, and reconciliation.
- Create deterministic per-idea git repositories and per-task branches, preserving them across runs.
- Stop active runs when task or idea state changes make them ineligible.
- Recover from transient failures with exponential backoff.
- Load runtime behavior from a repository-owned `WORKFLOW.md` contract.
- Expose operator-visible observability (structured logs at minimum).
- Provide a live activity feed on the public board showing what agents are actively working on.
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
   - Serves the public-facing board UI with live activity feed.
   - Manages board metadata (title, description).
   - Handles OAuth authentication for idea submission.
   - Stores ideas, tasks, upvotes, and moderation state.
   - Exposes APIs for the admin review interface.

2. **Identity Layer**
   - OAuth provider integration for authenticated actions (idea submission).
   - Anonymous identity tracking for upvote deduplication (fingerprint, session token, or IP-based).

3. **Idea Store**
   - Persists ideas and their lifecycle state.
   - Persists tasks within ideas and their lifecycle state.
   - Persists upvote counts and voter identity mappings.
   - Provides query interfaces for the board UI, admin review, and orchestrator dispatch.

4. **Admin Interface**
   - Kanban-style board showing tasks across status columns (Backlog, In Progress, Done, Failed, Cancelled).
   - Scrollable ideas list at top showing all ideas with status badges and quick-approve actions.
   - Inline task creation at the bottom of the Backlog column with idea selector.
   - Pending idea review queue with approve/reject actions.
   - Board settings management.
   - Orchestrator status display (running count, available slots, poll interval).

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
   - Reads pending tasks from the Task Store.
   - Decides which tasks to dispatch, retry, stop, or release.
   - Tracks session metrics and retry queue state.
   - Broadcasts activity events for the live feed.

8. **Workspace Manager**
   - Maps idea identifiers to git repository paths (one repo per idea).
   - Ensures per-idea git repositories exist (initializes with empty commit).
   - Creates per-task branches within idea repos.
   - Returns to main branch after task completion.
   - Cleans workspaces for terminal ideas.

9. **Agent Runner**
   - Ensures idea repo exists.
   - Creates task branch within idea repo.
   - Builds prompt from task + idea + workflow template.
   - Launches the coding agent subprocess.
   - Streams agent output back to the orchestrator.

10. **Status Surface** (optional)
    - Presents human-readable runtime status for the board owner/operator.

11. **Logging**
    - Emits structured runtime logs to one or more configured sinks.

### 3.2 Abstraction Layers

1. **Presentation Layer** (public board + admin kanban)
   - Board UI: title, description, idea list with task progress, live activity feed, submission form.
   - Admin UI: kanban board with task columns, ideas list, review queue, board settings.

2. **Identity & Access Layer** (OAuth + anonymous tracking)
   - Authenticated users: submit ideas.
   - Anonymous visitors: view board, upvote (once per identity per idea).
   - Board owner: approve/reject ideas, create/manage tasks, configure board, view orchestrator status.

3. **Data Layer** (idea store + task store)
   - Ideas, tasks, upvotes, moderation decisions, board metadata.

4. **Policy Layer** (repo-defined)
   - `WORKFLOW.md` prompt body.
   - Team-specific rules for idea handling, validation, and handoff.

5. **Configuration Layer** (typed getters)
   - Parses front matter into typed runtime settings.
   - Handles defaults, environment tokens, and path normalization.

6. **Coordination Layer** (orchestrator)
   - Polling loop, task eligibility, concurrency, retries, reconciliation.

7. **Execution Layer** (workspace + agent subprocess)
   - Per-idea git repos, per-task branches, workspace preparation, coding-agent protocol.

8. **Observability Layer** (logs + optional status surface)
   - Operator visibility into orchestrator and agent behavior.

### 3.3 External Dependencies

- OAuth provider(s) (e.g., GitHub, Google) for authenticated idea submission.
- Persistent storage backend for the Idea Store and Task Store (database, file-backed store, or hosted service).
- Local filesystem for workspaces and logs.
- Git CLI for per-idea repository and per-task branch management.
- Coding-agent executable (e.g., Claude Code CLI) that accepts prompts via stdin or file.
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

A project idea proposed by a community member or the board owner. Each idea represents a body of work that may contain many tasks. Each idea gets its own git repository.

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
- `repo_path` (string or null) — Filesystem path to this idea's git repository, set when workspace is first created.
- `created_at` (timestamp)
- `updated_at` (timestamp)
- `approved_at` (timestamp or null)
- `resolved_at` (timestamp or null)

Relationships:

- Has many Tasks.

#### 4.1.4 Idea Status (Enum)

Lifecycle states for an idea:

- `pending` — Submitted, awaiting board owner review. Visible on board but marked as pending.
- `approved` — Board owner has approved. Tasks can be created and dispatched.
- `in_progress` — At least one task is actively running.
- `completed` — All tasks finished successfully (or board owner marked complete).
- `rejected` — Board owner declined the idea. Optionally visible with rejection reason.
- `archived` — Removed from active view. Not eligible for dispatch.

State transition rules:

- `pending` -> `approved` | `rejected` (board owner action)
- `approved` -> `in_progress` (automatic when first task dispatches) | `archived` (board owner)
- `in_progress` -> `completed` | `approved` (all tasks done or released) | `archived` (board owner)
- `completed` -> `archived` (board owner)
- `rejected` -> `pending` (board owner reconsiders) | `archived`

#### 4.1.5 Task

A discrete unit of work within an idea. Tasks are the atoms of dispatch — each task is sent to exactly one coding agent instance. Multiple tasks within the same idea can run in parallel on separate branches.

Fields:

- `id` (string) — Stable internal ID (UUID or similar).
- `title` (string) — Short summary of what needs to be done.
- `description` (string or null) — Detailed instructions or context for the agent.
- `status` (TaskStatus enum)
- `idea_id` (string) — Foreign key to the parent idea.
- `branch_name` (string or null) — Git branch within the idea's repo. Auto-generated on dispatch (e.g., `task/<id_prefix>-<slugified_title>`).
- `agent_output` (string or null) — Captured stdout from the coding agent.
- `error` (string or null) — Error message if the task failed.
- `attempt` (integer, default: 0) — Number of dispatch attempts (incremented on each retry).
- `started_at` (timestamp or null)
- `completed_at` (timestamp or null)
- `created_at` (timestamp)
- `updated_at` (timestamp)

Relationships:

- Belongs to an Idea.

#### 4.1.6 Task Status (Enum)

Lifecycle states for a task:

- `pending` — Created, waiting to be dispatched by the orchestrator.
- `running` — Dispatched to a coding agent, actively executing.
- `completed` — Agent finished successfully (exit code 0).
- `failed` — Agent exited with non-zero code or was terminated due to stall.
- `cancelled` — Manually cancelled by the board owner.

State transition rules:

- `pending` -> `running` (orchestrator dispatch) | `cancelled` (board owner)
- `running` -> `completed` (agent exit 0) | `failed` (agent non-zero exit or stall)
- `failed` -> `running` (retry dispatch) | `cancelled` (board owner)
- `completed` and `cancelled` are terminal states.

#### 4.1.7 Submitter Identity

Fields:

- `user_id` (string) — OAuth provider user ID.
- `provider` (string) — OAuth provider name (e.g., `github`, `google`).
- `display_name` (string) — Public display name.
- `avatar_url` (string or null)

#### 4.1.8 Upvote

Fields:

- `idea_id` (string)
- `voter_identity` (string) — For authenticated users: `oauth:<provider>:<user_id>`. For anonymous: `anon:<fingerprint|session|ip>`.
- `created_at` (timestamp)

Constraints:

- Unique on `(idea_id, voter_identity)`. Duplicate upvote attempts are idempotent (no error, no second count).
- Upvotes are permitted on ideas in any visible status (`pending`, `approved`, `in_progress`, `completed`). Not permitted on `rejected` or `archived`.

#### 4.1.9 Workflow Definition

Parsed `WORKFLOW.md` payload:

- `config` (map) — YAML front matter root object.
- `prompt_template` (string) — Markdown body after front matter, trimmed.

#### 4.1.10 Service Config (Typed View)

Typed runtime values derived from `WorkflowDefinition.config` plus environment resolution. See Section 6 for full schema.

#### 4.1.11 Workspace

Filesystem workspace: a git repository assigned to one idea, containing branches for each task.

Fields (logical):

- `path` (workspace path — the idea's git repo root)
- `workspace_key` (sanitized idea identifier)
- `created_now` (boolean, used to gate `after_create` hook)

#### 4.1.12 Run Attempt

One execution attempt for one task.

Fields (logical):

- `task_id`
- `idea_id`
- `idea_identifier`
- `branch_name`
- `attempt` (integer — incremented on each dispatch)
- `workspace_path`
- `started_at`
- `status`
- `error` (optional)

#### 4.1.13 Retry Entry

Scheduled retry state for a task. Keyed by `task_id`.

Fields:

- `task_id` (string)
- `attempt` (integer) — Current retry attempt number.
- `retry_at` (timestamp) — When this retry becomes eligible for dispatch.
- `reason` (string) — Why the previous attempt failed.

Backoff schedule: exponential with base 5 seconds, multiplier 4.

- Attempt 1: 5s
- Attempt 2: 20s
- Attempt 3: 80s
- Attempt 4: 320s

Tasks exceeding `max_retries` are not retried further.

#### 4.1.14 Orchestrator Runtime State

Single authoritative in-memory state owned by the orchestrator.

Fields:

- `config` (ServiceConfig)
- `board_id` (string or null)
- `prompt_template` (string)
- `running` (map `task_id -> RunnerState`) — Currently executing tasks.
- `claimed` (set of task IDs) — Reserved but not yet running.
- `retry_attempts` (map `task_id -> RetryEntry`)
- `completed` (set of task IDs; bookkeeping only)
- `run_history` (list of recent run summaries, capped at 20)
- `totals` (aggregate metrics)

### 4.2 Stable Identifiers and Normalization Rules

- **Idea ID**: Use for internal map keys and store lookups.
- **Idea Identifier**: Use for human-readable display and workspace naming. Format: `IDEA-<sequential_number>` (zero-padded optional).
- **Task ID**: Use for orchestrator state keys, dispatch tracking, and retry scheduling.
- **Workspace Key**: Derive from `idea.identifier` by replacing any character not in `[A-Za-z0-9._-]` with `_`.
- **Branch Name**: Derive from task ID and title: `task/<id_prefix>-<slugified_title>`.
- **Normalized Idea Status**: Compare after `trim` + `lowercase`.

## 5. Board Service Specification

### 5.1 Public Board Endpoints

The board service exposes a public-facing UI and corresponding API.

#### 5.1.1 Board View (`GET /`)

Displays:

- Board title and description (Markdown rendered).
- List of visible ideas grouped or sorted by status and popularity.
- Each idea shows: identifier, title, status badge, upvote count with vote button, submitter display name, tags, task progress summary (running/done/queued/failed counts), and timestamps.
- Live activity feed showing real-time agent work (task started, working, completed, failed events).
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
- If `in_progress` or `completed`: summary of task statuses and agent work activity.

#### 5.1.3 Idea Submission (`POST /api/ideas`)

Requires: Valid OAuth session.

Request body:

- `title` (string, required, 5-200 characters)
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

#### 5.2.1 Admin Board (`GET /admin`)

Displays a unified admin interface with three tabs:

**Board Tab (Kanban):**

- Scrollable vertical ideas list at the top showing all ideas with identifier, title, status badge, and quick-approve button for pending ideas.
- Kanban columns for task statuses: Backlog (pending), In Progress (running), Done (completed), Failed, Cancelled.
- Each column shows task cards with: title, parent idea identifier, description preview, branch name, error message (if failed), agent output (collapsible), and timestamp.
- Columns size to their content (no fixed height), with scrollable card areas (max 60vh).
- "New task" button at the bottom of the Backlog column that expands into an inline creation form with idea selector, title, and description fields.
- Cancel button on pending and failed task cards.
- Orchestrator status in the header: running task count, available slots, poll interval.

**Review Tab:**

- Pending ideas queue with approve/reject buttons.
- Shows idea identifier, title, description, submitter, and upvote count.
- Badge count of pending ideas on the tab.

**Settings Tab:**

- Board title and description editor.

#### 5.2.2 Review Queue (`GET /admin/review`)

Returns all ideas in `pending` status, sorted by `created_at` ascending (oldest first).

Each item shows: identifier, title, description preview, submitter identity, upvote count, tags, submitted timestamp.

#### 5.2.3 Batch Review (`POST /admin/review/batch`)

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

#### 5.2.4 Task Management

Tasks are created and managed through the admin interface:

- `POST /admin/ideas/:idea_id/tasks` — Create a new task within an approved or in_progress idea.
- `DELETE /admin/tasks/:id` — Cancel a pending or failed task.

Task creation requires:

- `title` (string, required, min 3 characters)
- `description` (string, optional)
- Parent idea must be in `approved` or `in_progress` status.

#### 5.2.5 Idea Management (`PATCH /admin/ideas/:id`)

Allows the board owner to update any idea field:

- `priority` (integer or null)
- `tags` (list of strings)
- `status` (must follow valid state transitions from Section 4.1.4)
- `admin_notes` (string)
- `title`, `description` (editorial override)

#### 5.2.6 Board Settings (`GET/PATCH /admin/settings`)

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

- The orchestrator still reads dispatch candidates from the Task Store (not the external tracker).
- The workflow prompt may instruct the agent to create/update external tracker issues as part of its work.
- Reconciliation checks the Task Store, not the external tracker.

#### 6.3.3-6.3.6

`polling`, `workspace`, `hooks`, `agent`, `codex` — Identical to Symphony Sections 5.3.2-5.3.6.

### 6.4 Prompt Template Contract

The Markdown body of `WORKFLOW.md` is the per-task prompt template.

Template input variables:

- `idea` (object) — All Idea fields from Section 4.1.3 (replaces `issue`).
- `task` (object) — Task title and description, providing specific instructions for this unit of work.
- `attempt` (integer or null)
- `board` (object) — Board title and description, for context.

Rendering rules are identical to Symphony Section 5.4.

### 6.5 Workflow Validation and Error Surface

Identical to Symphony Section 5.5.

## 7. Orchestration State Machine

The orchestrator dispatches tasks (not ideas). Ideas transition to `in_progress` automatically when their first task is dispatched.

### 7.1 Task Orchestration States

Internal claim states:

1. `Unclaimed` — Task is not running and has no retry scheduled.
2. `Claimed` — Orchestrator has reserved the task for dispatch.
3. `Running` — Agent subprocess exists for this task.
4. `RetryQueued` — Agent is not running, but a retry timer exists.
5. `Released` — Claim removed.

### 7.2 Run Attempt Lifecycle

For each task dispatch:

1. Orchestrator claims the task.
2. Task status transitions to `running`, branch name and attempt number are set.
3. Parent idea transitions to `in_progress` (if currently `approved`).
4. Workspace manager ensures the idea's git repo exists.
5. Workspace manager creates the task's branch within the repo.
6. Agent runner builds the prompt and launches the subprocess.
7. Agent stdout is streamed and buffered.
8. On agent exit:
   - Exit 0: Task marked `completed`, output saved, workspace returns to main branch.
   - Non-zero exit: Task marked `failed`, error recorded, retry scheduled (if under max_retries), workspace returns to main branch.

### 7.3 Transition Triggers

- **Poll tick**: Discovers pending tasks and dispatches them.
- **Agent exit (success)**: Marks task completed, broadcasts activity.
- **Agent exit (failure)**: Marks task failed, schedules retry, broadcasts activity.
- **Stall timeout**: Running task exceeds `stall_timeout_ms` without activity. Treated as failure.
- **Admin cancel**: Board owner cancels a pending or failed task. Orchestrator releases claim.
- **Admin status change on idea**: If the board owner archives an in-progress idea, reconciliation detects this and stops all active tasks for that idea.

### 7.4 Idempotency and Recovery Rules

Identical to Symphony Section 7.4, applied to tasks instead of issues.

## 8. Polling, Scheduling, and Reconciliation

### 8.1 Poll Loop

Tick sequence:

1. Reconcile running tasks (stall detection, idea status refresh).
2. Process due retries.
3. Fetch pending tasks from Task Store.
4. Filter out tasks already running or claimed.
5. Dispatch eligible tasks while concurrency slots remain.
6. Update task and idea statuses.
7. Broadcast activity events.

### 8.2 Candidate Selection Rules

A task is dispatch-eligible only if all are true:

- It has status `pending`.
- Its parent idea has status `approved` or `in_progress`.
- It is not already in `running`.
- It is not already in `claimed`.
- Global concurrency slots are available.

Tasks are dispatched in insertion order (oldest first). The dispatch priority modes (manual, upvotes, hybrid) from Section 6.3.1 apply to idea-level prioritization when determining which ideas' tasks to dispatch first, but within an idea, tasks dispatch in creation order.

### 8.3 Concurrency Control

Identical to Symphony Section 8.3. The `max_concurrent_agents` setting limits the total number of simultaneously running tasks across all ideas.

### 8.4 Retry and Backoff

Identical to Symphony Section 8.4, applied to tasks. Each failed task is independently retried up to `max_retries` times with exponential backoff.

### 8.5 Active Run Reconciliation

Two parts:

**Part A: Stall detection**

For each running task, check if elapsed time exceeds `stall_timeout_ms`. If stalled:

1. Stop the agent subprocess.
2. Mark task as failed with "stall timeout" error.
3. Return workspace to main branch.
4. Schedule retry.

**Part B: Idea status refresh**

For each running task, check its parent idea's status:

- If idea is terminal (`completed`, `archived`): terminate agent, mark task failed.
- If idea is `rejected` or `pending`: terminate agent, mark task failed.
- If idea is active (`approved`, `in_progress`): continue.

### 8.6 Startup Workspace Cleanup

On startup, query the Idea Store for ideas in terminal statuses (`completed`, `archived`). Remove corresponding workspace directories.

## 9. Workspace Management and Safety

### 9.1 Per-Idea Git Repositories

Each idea gets its own persistent git repository under the configured workspace root:

- Path: `<workspace_root>/<sanitized_idea_identifier>/`
- Initialized with `git init` and an empty initial commit.
- The repo persists across task runs and retries.

### 9.2 Per-Task Branches

Each task dispatched within an idea creates a branch:

- Branch name format: `task/<task_id_prefix>-<slugified_task_title>`
- Created with `git checkout -b <branch_name>` from the main branch.
- After task completion (success or failure), workspace returns to main branch via `git checkout main`.
- Branches are preserved after completion for review.

### 9.3 Safety Invariants

- **Root containment**: All workspace paths must be under the configured workspace root. Path traversal is prevented by validating that the resolved absolute path starts with the absolute workspace root.
- **Key sanitization**: Idea identifiers are sanitized by replacing any character not in `[A-Za-z0-9._-]` with `_`.
- **Branch isolation**: Tasks within the same idea run on separate branches, preventing conflicts when tasks run in parallel.

### 9.4 Workspace Cleanup

- `clean(root, idea)`: Removes the entire idea repo directory (with path containment check).
- `clean_by_key(root, workspace_key)`: Same, by sanitized key.
- Only performed for ideas in terminal states.

## 10. Agent Runner Protocol (Coding Agent Integration)

### 10.1 Agent Subprocess Lifecycle

For each task dispatch:

1. Ensure the idea's git repo exists (`Workspace.ensure_repo`).
2. Create the task's branch (`Workspace.create_branch`).
3. Render the prompt template with idea, task, board, and attempt variables.
4. Append task-specific instructions (title, description) to the rendered prompt.
5. Write the prompt to a file in the workspace (`.chorus_prompt.md`).
6. Launch the agent subprocess with the workspace as cwd.
7. Capture stdout line-by-line via Erlang port (or equivalent).
8. On subprocess exit, handle success/failure.

### 10.2 Agent Command

The agent command is configurable via `WORKFLOW.md` front matter (`agent.command`). Default: `claude`.

For Claude Code, the launch command is:

```
cd <workspace_path> && cat .chorus_prompt.md | claude -p --verbose
```

### 10.3 Output Handling

- Agent stdout is captured line-by-line and buffered.
- The last output line and full buffer are tracked in runner state.
- Activity events are broadcast via PubSub for the live feed.
- On completion, the full output buffer is saved to the task's `agent_output` field.

## 11. Idea Store and Task Store Contract

### 11.1 Required Idea Operations

1. `fetch_candidate_ideas()` — Return ideas with status `approved` or `in_progress`.
2. `fetch_ideas_by_statuses(statuses)` — Used for startup cleanup and admin queries.
3. `fetch_idea_statuses_by_ids(idea_ids)` — Used for active-run reconciliation.
4. `create_idea(idea)` — Insert a new idea (from submission endpoint). Auto-generates sequential `IDEA-NNN` identifier.
5. `update_idea(idea_id, changes)` — Update idea fields (from admin actions, orchestrator status transitions).
6. `transition_status(idea_id, new_status)` — Validates against state machine before applying.
7. `create_upvote(idea_id, voter_identity)` — Idempotent upvote creation.
8. `delete_upvote(idea_id, voter_identity)` — Upvote removal.
9. `list_visible_ideas(board_id)` — Ideas for public display, sorted by status group then popularity.
10. `list_pending_ideas(board_id)` — Ideas awaiting review.

### 11.2 Required Task Operations

1. `create_task(attrs)` — Insert a new task within an idea.
2. `start_task(task_id)` — Transition to `running`, generate branch name, increment attempt.
3. `complete_task(task_id, output)` — Transition to `completed`, save agent output.
4. `fail_task(task_id, error)` — Transition to `failed`, save error message.
5. `cancel_task(task_id)` — Transition to `cancelled`.
6. `fetch_pending_tasks()` — Return tasks with status `pending`, preloading parent idea. Ordered by insertion time.
7. `fetch_running_tasks()` — Return tasks with status `running`, preloading parent idea.
8. `list_all_tasks_grouped()` — Return all tasks grouped by status, preloading parent idea. Used for kanban display.
9. `list_tasks(idea_id)` — Return tasks for a specific idea.
10. `count_by_status(idea_id)` — Task count breakdown for an idea (used for progress display).
11. `recent_activity(limit)` — Recent running/completed/failed tasks for activity feed.

### 11.3 Storage Backend

The spec does not prescribe a specific storage backend. Conforming options include:

- Relational database (PostgreSQL, SQLite, etc.)
- Document store (MongoDB, etc.)
- File-backed JSON/YAML store (for simple single-operator deployments)
- Hosted service with API (Supabase, Firebase, etc.)

Requirements:

- ACID-like guarantees for upvote deduplication (unique constraint on `(idea_id, voter_identity)`).
- Efficient query by status for task dispatch candidate fetching.
- Support for batch reads and writes for admin review.
- Foreign key integrity between tasks and ideas.

### 11.4 External Tracker Sync (Optional)

If `tracker` is configured in `WORKFLOW.md`:

- The orchestrator does NOT read from the external tracker for dispatch decisions.
- The workflow prompt may instruct the agent to create/update issues in the external tracker.
- An optional sync hook (`hooks.after_run`) can reconcile Idea Store status with external tracker state.

## 12. Prompt Construction and Context Assembly

### 12.1 Inputs

- `workflow.prompt_template`
- Normalized `idea` object (all fields from Section 4.1.3)
- `task` object (title, description from Section 4.1.5)
- `attempt` (integer or null)
- `board` (object with `title` and `description`)

### 12.2 Rendering Rules

Identical to Symphony Section 12.2. Template variables use `{{variable.field}}` syntax.

### 12.3 Task-Specific Prompt Augmentation

After rendering the workflow template, the agent runner appends task-specific instructions:

```markdown
## Current Task

**Title:** <task.title>
**Description:** <task.description>
**Branch:** <task.branch_name>
**Attempt:** <task.attempt>
```

This ensures the agent has clear context about the specific unit of work, even when the workflow template is shared across all tasks.

### 12.4 Retry/Continuation Semantics

Identical to Symphony Section 12.3.

### 12.5 Failure Semantics

Identical to Symphony Section 12.4.

## 13. Logging, Status, and Observability

Identical to Symphony Section 13, with the following additions:

### 13.1 Board-Specific Logging

Required additional log events:

- Idea submitted (with `idea_id`, `submitted_by`).
- Idea approved/rejected (with `idea_id`, batch context if applicable).
- Upvote created/removed (with `idea_id`, anonymized voter identity).
- Task created (with `task_id`, `idea_id`).
- Task dispatched (with `task_id`, `idea_identifier`, `branch_name`).
- Task completed/failed (with `task_id`, `duration`, `exit_code`).

### 13.2 Public Board Status

The public board UI should display:

- For each idea: task progress summary (e.g., "2 running, 3 done, 1 queued").
- Live activity feed showing real-time task events (started, working, completed, failed) with task title, parent idea, and timestamps.
- Detailed agent telemetry (tokens, session IDs, etc.) is only shown in the admin/operator view, not publicly.

### 13.3 Admin Dashboard

The admin interface should include:

- Pending review queue count badge.
- Kanban board with all tasks across status columns.
- Scrollable ideas list with status indicators.
- Running agent session summary (from orchestrator snapshot).
- Orchestrator stats: running count, available slots, poll interval.
- Run history for recently completed/failed tasks.

### 13.4 Activity Broadcasting

The orchestrator broadcasts activity events via PubSub to two topics:

- `board:<board_id>` — Idea and task state changes (for admin refresh).
- `activity:feed` — Real-time task activity events (for public live feed).

Activity event payload:

```
{
  event: "started" | "working" | "completed" | "failed" | "stalled",
  task_title: string,
  idea_identifier: string,
  idea_title: string,
  branch: string,
  last_output: string | null,
  timestamp: datetime
}
```

### 13.5 Optional HTTP API

If an HTTP server is implemented (per Symphony Section 13.7), the following additional endpoints are recommended:

- `GET /api/v1/board` — Board metadata and aggregate stats (total ideas, breakdown by status, total upvotes).
- `GET /api/v1/ideas` — Paginated list of visible ideas with upvote counts, status, and task progress.
- `GET /api/v1/ideas/:identifier` — Full idea detail with task list and agent status.

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

8. **Task Execution Failures**
   - Agent subprocess crash (non-zero exit): retry with backoff.
   - Agent stall (exceeds timeout): force-terminate, retry with backoff.
   - Git branch conflict: fail task, do not auto-retry (requires manual intervention).
   - Workspace corruption: clean and re-initialize repo on next dispatch.

### 14.2 Board-Specific Recovery

- OAuth provider unavailable: Show error on login/submit, allow anonymous browsing and upvoting to continue.
- Idea Store write failure on upvote: Return error to client, do not increment count. Client may retry.
- Partial batch review failure: Return per-action results. Successful actions are committed. Failed actions include error details.
- Task retry exhaustion: Task remains in `failed` status. Board owner can manually create a new task or investigate.

### 14.3 Restart Recovery

On orchestrator restart:

- In-memory state is empty (running, claimed, retry_attempts are all cleared).
- Tasks left in `running` status in the database are stale — they should be detected and failed on the next reconciliation tick.
- Pending tasks will be picked up normally by the poll loop.
- Workspaces for terminal ideas can be cleaned up during startup.

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
- Task titles are visible on the public activity feed. Task descriptions may contain implementation details and should be admin-only.
- Submitter email addresses are never exposed publicly.
- Admin notes and internal orchestrator details (session IDs, token counts, workspace paths) are never exposed publicly.
- Voter identities (including anonymous fingerprints) are never exposed publicly.

### 15.3 Workspace Security

- Per-idea git repos are isolated from each other and from the host project repo.
- Workspace root path is configurable and should not overlap with the service's own source code.
- Agent subprocesses run with the host user's permissions; sandbox controls are the responsibility of the agent and host OS.

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

### 17.2 Task Lifecycle Tests (Core Conformance)

- Task creation requires parent idea in `approved` or `in_progress` status.
- Task start generates branch name and increments attempt.
- Task completion saves agent output.
- Task failure saves error message.
- Task cancellation is only valid from `pending` or `failed` status.
- Multiple tasks within same idea can exist in different statuses.

### 17.3 Dispatch Priority Tests (Core Conformance)

- `manual` mode sorts by `priority` ascending, then `approved_at`.
- `upvotes` mode sorts by `upvote_count` descending, then `approved_at`.
- `hybrid` mode produces correct composite scores.
- Changing `dispatch_priority_mode` at runtime affects next dispatch cycle.

### 17.4 Workspace Tests (Core Conformance)

- Per-idea git repo creation is idempotent.
- Per-task branch creation works.
- Return to main branch after task completion.
- Workspace cleanup removes repo directory.
- Path containment prevents directory traversal.

### 17.5 Integration Tests (Core Conformance)

- Idea submitted -> approved -> task created -> task dispatched -> idea transitions to in_progress.
- Multiple tasks dispatched in parallel within same idea, each on own branch.
- Task completed -> agent output saved -> activity broadcast.
- Task failed -> retry scheduled -> retry dispatched after backoff.
- Idea archived while tasks running -> active tasks terminated.
- Live activity feed receives real-time task events.

## 18. Implementation Checklist (Definition of Done)

### 18.1 Required for Conformance

Everything from Symphony Section 18.1 (with "issue" -> "task" for dispatch), plus:

- Board service with title, description, and idea listing.
- Task entity with full lifecycle (pending -> running -> completed/failed/cancelled).
- Per-idea git repositories with per-task branches.
- Kanban-style admin interface for task management.
- OAuth integration for at least one provider.
- Idea submission with validation and rate limiting.
- Upvote/remove-upvote with deduplication.
- Review interface for board owner (approve/reject ideas).
- Task creation interface for board owner.
- Idea Store and Task Store with required operations.
- Configurable dispatch priority modes (`manual`, `upvotes`, `hybrid`).
- Orchestrator dispatches tasks (not ideas) from Task Store.
- Automatic idea status transition to `in_progress` on first task dispatch.
- Public board displays task progress per idea and live activity feed.
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
- TODO: Task dependency graph (sequential task ordering within an idea).
- TODO: PR auto-creation from completed task branches.
- TODO: Diff viewer for task branch changes in admin UI.
