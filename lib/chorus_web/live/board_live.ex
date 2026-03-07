defmodule ChorusWeb.BoardLive do
  use ChorusWeb, :live_view

  on_mount {ChorusWeb.Plugs.AssignUser, :default}

  alias Chorus.{Boards, Ideas, Tasks}

  @impl true
  def mount(_params, session, socket) do
    board = Boards.get_default_board()

    if is_nil(board) do
      {:ok, socket |> put_flash(:error, "No board configured. Run: mix run priv/repo/seeds.exs") |> assign(board: nil, ideas: [], activity: [], show_submit: false, submitted_message: false, is_admin: false)}
    else
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Chorus.PubSub, "board:#{board.id}")
        Phoenix.PubSub.subscribe(Chorus.PubSub, "activity:feed")
      end

      ideas = Ideas.list_visible_ideas(board.id) |> load_task_summaries()
      current_user = socket.assigns.current_user
      voter_id = session["voter_identity"] || "anon:session:#{:crypto.strong_rand_bytes(8) |> Base.url_encode64()}"

      voter =
        case current_user do
          nil -> voter_id
          user -> "oauth:github:#{user["id"]}"
        end

      upvoted_ids =
        ideas
        |> Enum.filter(fn idea -> Ideas.has_upvoted?(idea.id, voter) end)
        |> MapSet.new(& &1.id)

      {:ok,
       socket
       |> assign(
         board: board,
         ideas: ideas,
         is_admin: admin?(current_user),
         voter_identity: voter_id,
         upvoted_ids: upvoted_ids,
         show_submit: false,
         submitted_message: false,
         activity: Tasks.recent_activity(15),
         form: to_form(%{"title" => "", "description" => "", "tags" => ""})
       )}
    end
  end

  @impl true
  def handle_event("dismiss_submitted", _, socket) do
    {:noreply, assign(socket, submitted_message: false)}
  end

  def handle_event("toggle_submit", _, socket) do
    {:noreply, assign(socket, show_submit: !socket.assigns.show_submit)}
  end

  def handle_event("submit_idea", %{"title" => title, "description" => desc, "tags" => tags}, socket) do
    board = socket.assigns.board
    user = socket.assigns.current_user

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "Sign in to submit ideas")}
    else
      tag_list = tags |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      case Ideas.create_idea(%{
             title: title,
             description: desc,
             tags: tag_list,
             submitted_by_user_id: user["id"],
             submitted_by_provider: "github",
             submitted_by_display_name: user["name"],
             submitted_by_avatar_url: user["avatar_url"],
             board_id: board.id
           }) do
        {:ok, _idea} ->
          Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{board.id}", :ideas_updated)

          {:noreply,
           socket
           |> reload_ideas()
           |> assign(show_submit: false, submitted_message: true, form: to_form(%{"title" => "", "description" => "", "tags" => ""}))}

        {:error, changeset} ->
          errors = Chorus.Helpers.changeset_errors(changeset)
          {:noreply, put_flash(socket, :error, "Error: #{inspect(errors)}")}
      end
    end
  end

  def handle_event("upvote", %{"id" => idea_id}, socket) do
    voter = voter_identity(socket)

    if idea_id in socket.assigns.upvoted_ids do
      Ideas.delete_upvote(idea_id, voter)
      upvoted = MapSet.delete(socket.assigns.upvoted_ids, idea_id)
      Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{socket.assigns.board.id}", :ideas_updated)
      {:noreply, socket |> reload_ideas() |> assign(upvoted_ids: upvoted)}
    else
      case Ideas.create_upvote(idea_id, voter) do
        {:ok, _} ->
          upvoted = MapSet.put(socket.assigns.upvoted_ids, idea_id)
          Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{socket.assigns.board.id}", :ideas_updated)
          {:noreply, socket |> reload_ideas() |> assign(upvoted_ids: upvoted)}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info(:ideas_updated, socket) do
    {:noreply, reload_ideas(socket)}
  end

  def handle_info({:activity, activity}, socket) do
    updated = [activity | socket.assigns.activity] |> Enum.take(30)
    {:noreply, assign(socket, activity: updated)}
  end

  defp reload_ideas(socket) do
    ideas = Ideas.list_visible_ideas(socket.assigns.board.id) |> load_task_summaries()
    assign(socket, ideas: ideas)
  end

  defp load_task_summaries(ideas) do
    Enum.map(ideas, fn idea ->
      counts = Tasks.count_by_status(idea.id)
      Map.put(idea, :task_summary, counts)
    end)
  end

  defp voter_identity(socket) do
    case socket.assigns.current_user do
      nil -> socket.assigns.voter_identity
      user -> "oauth:github:#{user["id"]}"
    end
  end

  defp admin?(nil), do: false
  defp admin?(user) do
    case Application.get_env(:chorus, :admin_github_id) do
      nil -> false
      "" -> false
      admin_id -> user["id"] == admin_id
    end
  end

  defp status_badge_class(status) do
    case status do
      "pending" -> "badge-warning"
      "approved" -> "badge-info"
      "in_progress" -> "badge-primary"
      "completed" -> "badge-success"
      "rejected" -> "badge-error"
      _ -> "badge-ghost"
    end
  end

  defp status_label(status) do
    case status do
      "in_progress" -> "In Progress"
      other -> String.capitalize(other)
    end
  end

  defp event_badge_class(event) do
    case event do
      "started" -> "badge-info"
      "working" -> "badge-primary"
      "completed" -> "badge-success"
      "failed" -> "badge-error"
      "stalled" -> "badge-warning"
      "github_pull_request" -> "badge-accent"
      "github_push" -> "badge-neutral"
      "github_issue" -> "badge-secondary"
      "github_comment" -> "badge-ghost"
      _ -> "badge-ghost"
    end
  end

  defp event_display_name(event) do
    case event do
      "github_pull_request" -> "PR"
      "github_push" -> "push"
      "github_issue" -> "issue"
      "github_comment" -> "comment"
      other -> other
    end
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_time(%{timestamp: dt}), do: format_time(dt)
  defp format_time(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-6xl px-4 py-8">
        <%= if @board do %>
          <div class="mb-8">
            <h1 class="text-4xl font-bold mb-2">{@board.title}</h1>
            <%= if @board.description do %>
              <p class="text-base-content/70 text-lg">{raw(@board.description)}</p>
            <% end %>
            <div class="mt-4 flex gap-2">
              <%= if @current_user do %>
                <button phx-click="toggle_submit" class="btn btn-primary btn-sm">
                  <%= if @show_submit, do: "Cancel", else: "+ Submit Idea" %>
                </button>
                <div class="flex items-center gap-2 text-sm text-base-content/50">
                  <%= if @current_user["avatar_url"] do %>
                    <img src={@current_user["avatar_url"]} class="w-6 h-6 rounded-full" />
                  <% end %>
                  <span>{@current_user["name"]}</span>
                  <.link href="/auth/logout" class="link link-hover text-xs">Sign out</.link>
                </div>
              <% else %>
                <.link href="/auth/github" class="btn btn-primary btn-sm gap-2">
                  <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/></svg>
                  Sign in to submit ideas
                </.link>
              <% end %>
              <%= if @is_admin do %>
                <.link href="/admin" class="btn btn-ghost btn-sm ml-auto">
                  Admin
                </.link>
              <% end %>
            </div>
          </div>

          <%= if @show_submit do %>
            <div class="card bg-base-100 shadow-md mb-6">
              <div class="card-body">
                <h2 class="card-title text-lg">Submit an Idea</h2>
                <.form for={@form} phx-submit="submit_idea" class="space-y-4">
                  <div class="form-control">
                    <label class="label"><span class="label-text">Title</span></label>
                    <input type="text" name="title" value={@form["title"].value} placeholder="What's your idea?" class="input input-bordered w-full" required minlength="5" maxlength="200" />
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text">Description (optional)</span></label>
                    <textarea name="description" class="textarea textarea-bordered w-full" rows="4" placeholder="Describe your idea in more detail..." maxlength="10000">{@form["description"].value}</textarea>
                  </div>
                  <div class="form-control">
                    <label class="label"><span class="label-text">Tags (comma-separated, max 5)</span></label>
                    <input type="text" name="tags" value={@form["tags"].value} placeholder="ml, infrastructure, tooling" class="input input-bordered w-full" />
                  </div>
                  <button type="submit" class="btn btn-primary">Submit</button>
                </.form>
              </div>
            </div>
          <% end %>

          <%= if @submitted_message do %>
            <div class="alert alert-info mb-6 shadow-sm">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" /></svg>
              <span>Idea submitted! It will appear on the board once reviewed by the board owner.</span>
              <button phx-click="dismiss_submitted" class="btn btn-ghost btn-xs">Dismiss</button>
            </div>
          <% end %>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <%!-- Ideas list --%>
            <div class="lg:col-span-2 space-y-3">
              <h2 class="text-xl font-semibold">Ideas</h2>
              <%= if Enum.empty?(@ideas) do %>
                <div class="text-center py-16 text-base-content/50">
                  <p class="text-xl">No ideas yet</p>
                  <p>Be the first to submit one!</p>
                </div>
              <% else %>
                <%= for idea <- @ideas do %>
                  <div class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow">
                    <div class="card-body py-4 px-5 flex-row items-start gap-4">
                      <div class="flex flex-col items-center min-w-[3rem]">
                        <button
                          phx-click="upvote"
                          phx-value-id={idea.id}
                          class={"btn btn-ghost btn-sm px-2 #{if MapSet.member?(@upvoted_ids, idea.id), do: "text-primary", else: "text-base-content/40"}"}
                        >
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z" clip-rule="evenodd" />
                          </svg>
                        </button>
                        <span class="font-bold text-lg">{idea.upvote_count}</span>
                      </div>
                      <div class="flex-1 min-w-0">
                        <div class="flex items-center gap-2 mb-1">
                          <.link href={~p"/ideas/#{idea.identifier}"} class="font-semibold text-lg hover:underline truncate">
                            {idea.title}
                          </.link>
                          <span class={"badge badge-sm #{status_badge_class(idea.status)}"}>{status_label(idea.status)}</span>
                        </div>
                        <%= if idea.description do %>
                          <p class="text-base-content/60 text-sm line-clamp-2">{idea.description}</p>
                        <% end %>
                        <%= if idea.repo_url do %>
                          <a href={idea.repo_url} target="_blank" class="inline-flex items-center gap-1 mt-1 text-xs text-base-content/40 hover:text-base-content/70 font-mono truncate">
                            <svg class="w-3 h-3 flex-shrink-0" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/></svg>
                            {idea.repo_url |> String.replace("https://github.com/", "")}
                          </a>
                        <% end %>
                        <div class="flex items-center gap-3 mt-2 text-xs text-base-content/40">
                          <span class="font-mono">{idea.identifier}</span>
                          <span>by {idea.submitted_by_display_name}</span>
                          <%= for tag <- idea.tags do %>
                            <span class="badge badge-ghost badge-xs">{tag}</span>
                          <% end %>
                        </div>
                        <%!-- Task progress --%>
                        <%= if map_size(idea.task_summary) > 0 do %>
                          <div class="flex items-center gap-2 mt-2 text-xs">
                            <%= if idea.task_summary["running"] do %>
                              <span class="badge badge-primary badge-xs">{idea.task_summary["running"]} running</span>
                            <% end %>
                            <%= if idea.task_summary["completed"] do %>
                              <span class="badge badge-success badge-xs">{idea.task_summary["completed"]} done</span>
                            <% end %>
                            <%= if idea.task_summary["pending"] do %>
                              <span class="badge badge-ghost badge-xs">{idea.task_summary["pending"]} queued</span>
                            <% end %>
                            <%= if idea.task_summary["failed"] do %>
                              <span class="badge badge-error badge-xs">{idea.task_summary["failed"]} failed</span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>

            <%!-- Live activity feed --%>
            <div>
              <h2 class="text-xl font-semibold mb-3">Live Activity</h2>
              <div class="space-y-2">
                <%= if Enum.empty?(@activity) do %>
                  <div class="text-center py-8 text-base-content/40 text-sm">
                    <p>No recent activity</p>
                    <p>Activity will appear here as agents work on tasks</p>
                  </div>
                <% else %>
                  <%= for item <- @activity do %>
                    <div class="card bg-base-100 shadow-sm">
                      <div class="card-body py-2 px-3">
                        <div class="flex items-center gap-2">
                          <%= if is_map(item) && Map.has_key?(item, :event) do %>
                            <span class={"badge badge-xs #{event_badge_class(item.event)}"}>{event_display_name(item.event)}</span>
                            <span class="text-sm font-medium truncate">{item.idea_title || item.idea_identifier}</span>
                            <span class="text-xs text-base-content/40 ml-auto">{format_time(item)}</span>
                          <% else %>
                            <span class={"badge badge-xs #{status_badge_class(item.status)}"}>{item.status}</span>
                            <span class="text-sm font-medium truncate">{item.idea && (item.idea.title || item.idea.identifier)}</span>
                            <span class="text-xs text-base-content/40 ml-auto">
                              {Calendar.strftime(item.updated_at, "%H:%M:%S")}
                            </span>
                          <% end %>
                        </div>
                        <%= if is_map(item) && Map.has_key?(item, :event) do %>
                          <p class="text-xs text-base-content/60 truncate">{item.task_title}</p>
                          <%= if item.last_output && item.event not in ["working"] do %>
                            <p class="text-xs font-mono text-base-content/40 truncate">
                              <%= if String.starts_with?(item.event, "github_") do %>
                                by {item.last_output}
                              <% else %>
                                {item.last_output}
                              <% end %>
                            </p>
                          <% end %>
                          <%= if item[:summary] && item[:summary] != "" do %>
                            <p class="text-xs text-base-content/50 italic line-clamp-2">{item.summary}</p>
                          <% end %>
                        <% else %>
                          <.link href={~p"/tasks/#{item.id}"} class="text-xs text-base-content/60 truncate hover:underline">{item.title}</.link>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        <% else %>
          <div class="text-center py-16">
            <p class="text-xl">No board configured</p>
            <p>Run <code>mix run priv/repo/seeds.exs</code> to set up the default board.</p>
          </div>
        <% end %>
      </div>
      <footer class="text-center py-6 text-xs text-base-content/30">
        Powered by <a href="https://github.com/dimenwarper/chorus" target="_blank" class="link link-hover">Chorus</a>
      </footer>
    </div>
    """
  end
end
