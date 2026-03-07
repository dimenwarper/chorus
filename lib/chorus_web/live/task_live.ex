defmodule ChorusWeb.TaskLive do
  use ChorusWeb, :live_view

  on_mount {ChorusWeb.Plugs.AssignUser, :default}

  alias Chorus.{Repo, Tasks}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    task = Tasks.get_task!(id) |> Repo.preload(:idea)

    {:ok, assign(socket, task: task)}
  end

  defp status_badge_class(status) do
    case status do
      "pending" -> "badge-warning"
      "running" -> "badge-primary"
      "completed" -> "badge-success"
      "failed" -> "badge-error"
      "cancelled" -> "badge-ghost"
      _ -> "badge-ghost"
    end
  end

  defp format_datetime(nil), do: "—"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%b %d, %Y at %H:%M:%S UTC")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-3xl px-4 py-8">
        <div class="flex items-center gap-2 mb-4">
          <%= if @task.idea do %>
            <.link href={~p"/ideas/#{@task.idea.identifier}"} class="btn btn-ghost btn-sm">&larr; {@task.idea.title}</.link>
          <% else %>
            <.link href={~p"/"} class="btn btn-ghost btn-sm">&larr; Back</.link>
          <% end %>
        </div>

        <div class="card bg-base-100 shadow-md">
          <div class="card-body">
            <div class="flex items-center gap-3 mb-4">
              <span class={"badge #{status_badge_class(@task.status)}"}>{String.capitalize(@task.status)}</span>
              <span class="text-xs font-mono text-base-content/40">{String.slice(@task.id, 0, 8)}</span>
            </div>

            <h1 class="text-2xl font-bold mb-2">{@task.title}</h1>

            <%= if @task.description do %>
              <p class="text-base-content/60 mb-4 whitespace-pre-wrap">{@task.description}</p>
            <% end %>

            <div class="grid grid-cols-2 gap-4 text-sm mb-6">
              <div>
                <span class="text-base-content/40">Created</span>
                <p>{format_datetime(@task.inserted_at)}</p>
              </div>
              <div>
                <span class="text-base-content/40">Started</span>
                <p>{format_datetime(@task.started_at)}</p>
              </div>
              <div>
                <span class="text-base-content/40">Completed</span>
                <p>{format_datetime(@task.completed_at)}</p>
              </div>
              <div>
                <span class="text-base-content/40">Attempts</span>
                <p>{@task.attempt}</p>
              </div>
              <%= if @task.branch_name do %>
                <div class="col-span-2">
                  <span class="text-base-content/40">Branch</span>
                  <p class="font-mono text-sm">{@task.branch_name}</p>
                </div>
              <% end %>
              <%= if @task.pr_url do %>
                <div class="col-span-2">
                  <span class="text-base-content/40">Pull Request</span>
                  <p><a href={@task.pr_url} target="_blank" class="link link-primary">{@task.pr_url}</a></p>
                </div>
              <% end %>
            </div>

            <%= if @task.error do %>
              <div class="mb-6">
                <h2 class="text-lg font-semibold text-error mb-2">Error</h2>
                <pre class="bg-error/10 text-error text-sm p-4 rounded-lg overflow-x-auto whitespace-pre-wrap">{@task.error}</pre>
              </div>
            <% end %>

            <%= if @task.agent_output do %>
              <div>
                <h2 class="text-lg font-semibold mb-2">Agent Output</h2>
                <pre class="bg-base-200 text-sm p-4 rounded-lg overflow-x-auto whitespace-pre-wrap max-h-[70vh] overflow-y-auto">{@task.agent_output}</pre>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
