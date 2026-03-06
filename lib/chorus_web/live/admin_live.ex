defmodule ChorusWeb.AdminLive do
  use ChorusWeb, :live_view

  on_mount {ChorusWeb.Plugs.AssignUser, :require_auth}

  alias Chorus.{Boards, Ideas, Tasks}

  @columns [
    {"pending", "Backlog"},
    {"running", "In Progress"},
    {"completed", "Done"},
    {"failed", "Failed"},
    {"cancelled", "Cancelled"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    board = Boards.get_default_board()

    if is_nil(board) do
      {:ok, assign(socket, board: nil, tab: "board", columns: @columns, tasks_by_status: %{}, pending_ideas: [], all_ideas: [], actionable_ideas: [], orch_status: nil, adding_to_column: false, task_form: to_form(%{"title" => "", "description" => ""}))}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Chorus.PubSub, "board:#{board.id}")
        :timer.send_interval(5_000, self(), :refresh_orch)
      end

      {:ok,
       socket
       |> assign(board: board, tab: "board", columns: @columns, adding_to_column: false, task_form: to_form(%{"title" => "", "description" => ""}))
       |> reload_all()}
    end
  end

  defp reload_all(socket) do
    board = socket.assigns.board

    all_ideas = Ideas.list_visible_ideas(board.id)

    socket
    |> assign(
      pending_ideas: Ideas.list_pending_ideas(board.id),
      all_ideas: all_ideas,
      actionable_ideas: Enum.filter(all_ideas, &(&1.status in ["approved", "in_progress"])),
      tasks_by_status: Tasks.list_all_tasks_grouped()
    )
    |> load_orch_status()
  end

  defp load_orch_status(socket) do
    status =
      try do
        Chorus.Orchestrator.Server.status()
      catch
        :exit, _ -> nil
      end

    assign(socket, orch_status: status)
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_event("approve", %{"id" => idea_id}, socket) do
    case Ideas.transition_status(idea_id, "approved") do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{socket.assigns.board.id}", :ideas_updated)
        {:noreply, socket |> reload_all() |> put_flash(:info, "Idea approved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not approve idea")}
    end
  end

  def handle_event("reject", %{"id" => idea_id}, socket) do
    case Ideas.transition_status(idea_id, "rejected") do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{socket.assigns.board.id}", :ideas_updated)
        {:noreply, socket |> reload_all() |> put_flash(:info, "Idea rejected")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reject idea")}
    end
  end

  def handle_event("archive", %{"id" => idea_id}, socket) do
    case Ideas.transition_status(idea_id, "archived") do
      {:ok, _} ->
        Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{socket.assigns.board.id}", :ideas_updated)
        {:noreply, socket |> reload_all() |> put_flash(:info, "Idea archived")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not archive idea")}
    end
  end

  def handle_event("show_add_task_column", _, socket) do
    {:noreply, assign(socket, adding_to_column: true, task_form: to_form(%{"title" => "", "description" => ""}))}
  end

  def handle_event("cancel_add_task", _, socket) do
    {:noreply, assign(socket, adding_to_column: false)}
  end

  def handle_event("create_task", %{"title" => title, "description" => desc, "idea_id" => idea_id}, socket) do
    case Tasks.create_task(%{title: title, description: desc, idea_id: idea_id}) do
      {:ok, _task} ->
        Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{socket.assigns.board.id}", :ideas_updated)
        {:noreply,
         socket
         |> assign(adding_to_column: false)
         |> reload_all()
         |> put_flash(:info, "Task created")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(Chorus.Helpers.changeset_errors(changeset))}")}
    end
  end

  def handle_event("cancel_task", %{"id" => task_id}, socket) do
    case Tasks.cancel_task(task_id) do
      {:ok, _} ->
        {:noreply, reload_all(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cancel task")}
    end
  end

  def handle_event("update_board", %{"title" => title, "description" => desc}, socket) do
    case Boards.update_board(socket.assigns.board, %{title: title, description: desc}) do
      {:ok, board} -> {:noreply, socket |> assign(board: board) |> put_flash(:info, "Board updated")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update board")}
    end
  end

  @impl true
  def handle_info(:ideas_updated, socket) do
    {:noreply, reload_all(socket)}
  end

  def handle_info(:refresh_orch, socket) do
    {:noreply, reload_all(socket)}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tasks_for_status(tasks_by_status, status) do
    Map.get(tasks_by_status, status, [])
  end

  defp column_color(status) do
    case status do
      "pending" -> "border-base-300"
      "running" -> "border-primary"
      "completed" -> "border-success"
      "failed" -> "border-error"
      "cancelled" -> "border-base-300/50"
    end
  end

  defp column_dot_color(status) do
    case status do
      "pending" -> "bg-base-300"
      "running" -> "bg-primary"
      "completed" -> "bg-success"
      "failed" -> "bg-error"
      "cancelled" -> "bg-base-300/50"
    end
  end
  defp idea_status_style(status) do
    case status do
      "pending" -> "border-warning/30 bg-warning/5"
      "approved" -> "border-info/30 bg-info/5"
      "in_progress" -> "border-primary/30 bg-primary/5"
      "completed" -> "border-success/30 bg-success/5"
      "rejected" -> "border-error/30 bg-error/5"
      _ -> "border-base-300 bg-base-100"
    end
  end

  defp idea_status_badge(status) do
    case status do
      "pending" -> "badge-warning"
      "approved" -> "badge-info"
      "in_progress" -> "badge-primary"
      "completed" -> "badge-success"
      "rejected" -> "badge-error"
      _ -> "badge-ghost"
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-7xl px-4 py-6">
        <div class="flex items-center justify-between mb-4">
          <h1 class="text-2xl font-bold">Admin</h1>
          <div class="flex items-center gap-2">
            <%= if @orch_status do %>
              <div class="flex items-center gap-3 text-sm text-base-content/60 mr-4">
                <span class="flex items-center gap-1">
                  <span class="w-2 h-2 rounded-full bg-primary inline-block"></span>
                  {@orch_status.running} running
                </span>
                <span>{@orch_status.available_slots} slots free</span>
                <span>{@orch_status.config.poll_interval_ms / 1000}s poll</span>
              </div>
            <% end %>
            <.link href={~p"/"} class="btn btn-ghost btn-sm">&larr; Board</.link>
          </div>
        </div>

        <%= if @board do %>
          <div role="tablist" class="tabs tabs-bordered mb-4">
            <a role="tab" class={"tab #{if @tab == "board", do: "tab-active"}"} phx-click="switch_tab" phx-value-tab="board">
              Board
            </a>
            <a role="tab" class={"tab #{if @tab == "review", do: "tab-active"}"} phx-click="switch_tab" phx-value-tab="review">
              Review
              <%= if length(@pending_ideas) > 0 do %>
                <span class="badge badge-warning badge-sm ml-1">{length(@pending_ideas)}</span>
              <% end %>
            </a>
            <a role="tab" class={"tab #{if @tab == "settings", do: "tab-active"}"} phx-click="switch_tab" phx-value-tab="settings">
              Settings
            </a>
          </div>

          <%!-- KANBAN BOARD --%>
          <%= if @tab == "board" do %>
            <%!-- Ideas list --%>
            <div class="mb-4 max-h-48 overflow-y-auto rounded-lg border border-base-300 bg-base-100/50">
              <%= if Enum.empty?(@all_ideas) do %>
                <div class="px-4 py-3 text-sm text-base-content/40">No ideas yet</div>
              <% else %>
                <%= for idea <- @all_ideas do %>
                  <div class={"flex items-center gap-3 px-4 py-2 border-b border-base-200 last:border-b-0 #{idea_status_style(idea.status)}"}>
                    <span class="font-mono text-xs text-base-content/50 w-16 flex-shrink-0">{idea.identifier}</span>
                    <span class="text-sm flex-1 truncate">{idea.title}</span>
                    <span class={"badge badge-xs #{idea_status_badge(idea.status)} flex-shrink-0"}>{idea.status |> String.replace("_", " ")}</span>
                    <%= if idea.status == "pending" do %>
                      <button phx-click="approve" phx-value-id={idea.id} class="btn btn-success btn-xs px-1.5 flex-shrink-0" title="Approve">&#10003;</button>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>

            <%!-- Kanban columns --%>
            <div class="flex gap-4 overflow-x-auto pb-4 items-start">
              <%= for {status, label} <- @columns do %>
                <% tasks = tasks_for_status(@tasks_by_status, status) %>
                <div class={"flex flex-col min-w-[250px] w-[250px] rounded-lg border-t-2 #{column_color(status)} bg-base-100/50"}>
                  <%!-- Column header --%>
                  <div class="flex items-center gap-2 px-3 py-2">
                    <span class={"w-2.5 h-2.5 rounded-full #{column_dot_color(status)}"}></span>
                    <span class="font-semibold text-sm">{label}</span>
                    <span class="text-xs text-base-content/40">{length(tasks)}</span>
                  </div>

                  <%!-- Task cards --%>
                  <div class="px-2 pb-2 space-y-2 max-h-[60vh] overflow-y-auto">
                    <%= for task <- tasks do %>
                      <div class="card bg-base-100 shadow-sm border border-base-200">
                        <div class="card-body py-2.5 px-3">
                          <div class="flex items-start justify-between gap-1">
                            <div class="flex-1 min-w-0">
                              <p class="font-medium text-sm leading-tight">{task.title}</p>
                              <%= if task.idea do %>
                                <span class="font-mono text-xs text-base-content/40">{task.idea.identifier}</span>
                              <% end %>
                            </div>
                            <%= if status in ["pending", "failed"] do %>
                              <button phx-click="cancel_task" phx-value-id={task.id} class="btn btn-ghost btn-xs px-1 opacity-30 hover:opacity-100" title="Cancel">
                                &times;
                              </button>
                            <% end %>
                          </div>
                          <%= if task.description do %>
                            <p class="text-xs text-base-content/50 line-clamp-2 mt-0.5">{task.description}</p>
                          <% end %>
                          <%= if task.branch_name do %>
                            <p class="font-mono text-[10px] text-base-content/30 mt-1 truncate">{task.branch_name}</p>
                          <% end %>
                          <%= if task.error do %>
                            <p class="text-xs text-error mt-1 truncate" title={task.error}>{task.error}</p>
                          <% end %>
                          <%= if task.agent_output do %>
                            <details class="mt-1">
                              <summary class="text-[10px] text-base-content/30 cursor-pointer">output</summary>
                              <pre class="text-[10px] font-mono bg-base-200 p-1 rounded mt-1 max-h-24 overflow-y-auto whitespace-pre-wrap">{task.agent_output |> String.slice(0, 500)}</pre>
                            </details>
                          <% end %>
                          <div class="text-[10px] text-base-content/30 mt-1">
                            {Calendar.strftime(task.updated_at, "%b %d, %H:%M")}
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Add task button (only in Backlog column) --%>
                  <%= if status == "pending" do %>
                    <%= if @adding_to_column do %>
                      <div class="px-2 pb-2">
                        <div class="card bg-base-100 shadow-sm border border-base-200">
                          <div class="card-body py-2.5 px-3">
                            <.form for={@task_form} phx-submit="create_task" class="space-y-2">
                              <div class="form-control">
                                <select name="idea_id" class="select select-bordered select-xs w-full" required>
                                  <option value="" disabled selected>Select idea...</option>
                                  <%= for idea <- @actionable_ideas do %>
                                    <option value={idea.id}>{idea.identifier} — {idea.title |> String.slice(0, 30)}</option>
                                  <% end %>
                                </select>
                              </div>
                              <div class="form-control">
                                <input type="text" name="title" class="input input-bordered input-xs w-full" placeholder="Task title" required minlength="3" />
                              </div>
                              <div class="form-control">
                                <input type="text" name="description" class="input input-bordered input-xs w-full" placeholder="Description (optional)" />
                              </div>
                              <div class="flex gap-1">
                                <button type="submit" class="btn btn-primary btn-xs flex-1">Add</button>
                                <button type="button" phx-click="cancel_add_task" class="btn btn-ghost btn-xs">Cancel</button>
                              </div>
                            </.form>
                          </div>
                        </div>
                      </div>
                    <% else %>
                      <div class="px-2 pb-2">
                        <button phx-click="show_add_task_column" class="btn btn-ghost btn-xs w-full text-base-content/30 hover:text-base-content/60 gap-1 justify-start font-normal">
                          <span class="text-lg leading-none">+</span> New task
                        </button>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- REVIEW TAB --%>
          <%= if @tab == "review" do %>
            <div class="space-y-3">
              <%= if Enum.empty?(@pending_ideas) do %>
                <div class="text-center py-12 text-base-content/50">
                  <p class="text-lg">No ideas pending review</p>
                </div>
              <% else %>
                <%= for idea <- @pending_ideas do %>
                  <div class="card bg-base-100 shadow-sm">
                    <div class="card-body py-4 px-5">
                      <div class="flex items-start justify-between">
                        <div class="flex-1">
                          <div class="flex items-center gap-2 mb-1">
                            <span class="font-mono text-xs text-base-content/40">{idea.identifier}</span>
                            <h3 class="font-semibold">{idea.title}</h3>
                          </div>
                          <%= if idea.description do %>
                            <p class="text-sm text-base-content/60 line-clamp-2">{idea.description}</p>
                          <% end %>
                          <div class="text-xs text-base-content/40 mt-1">
                            by {idea.submitted_by_display_name} · {idea.upvote_count} upvotes
                          </div>
                        </div>
                        <div class="flex gap-2 ml-4">
                          <button phx-click="approve" phx-value-id={idea.id} class="btn btn-success btn-sm">Approve</button>
                          <button phx-click="reject" phx-value-id={idea.id} class="btn btn-error btn-sm btn-outline">Reject</button>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>

          <%!-- SETTINGS TAB --%>
          <%= if @tab == "settings" do %>
            <div class="card bg-base-100 shadow-sm max-w-xl">
              <div class="card-body">
                <h2 class="card-title">Board Settings</h2>
                <.form for={%{}} phx-submit="update_board" class="space-y-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text">Title</span></label>
                    <input type="text" name="title" value={@board.title} class="input input-bordered" />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text">Description</span></label>
                    <textarea name="description" class="textarea textarea-bordered" rows="3">{@board.description}</textarea>
                  </div>
                  <button type="submit" class="btn btn-primary btn-sm">Save</button>
                </.form>
              </div>
            </div>
          <% end %>
        <% else %>
          <p>No board configured.</p>
        <% end %>
      </div>
    </div>
    """
  end
end
