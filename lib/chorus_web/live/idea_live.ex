defmodule ChorusWeb.IdeaLive do
  use ChorusWeb, :live_view

  on_mount {ChorusWeb.Plugs.AssignUser, :default}

  alias Chorus.Ideas

  @impl true
  def mount(%{"identifier" => identifier}, session, socket) do
    idea = Ideas.get_idea_by_identifier!(identifier)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Chorus.PubSub, "board:#{idea.board_id}")
    end

    voter_id = session["voter_identity"] || "anon:session:anonymous"
    current_user = socket.assigns.current_user

    voter =
      case current_user do
        nil -> voter_id
        user -> "oauth:github:#{user["id"]}"
      end

    {:ok,
     socket
     |> assign(
       idea: idea,
       voter_identity: voter,
       upvoted: Ideas.has_upvoted?(idea.id, voter)
     )}
  end

  @impl true
  def handle_event("upvote", _, socket) do
    idea = socket.assigns.idea
    voter = socket.assigns.voter_identity

    if socket.assigns.upvoted do
      Ideas.delete_upvote(idea.id, voter)
      refreshed = Ideas.get_idea_by_identifier!(idea.identifier)
      Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{idea.board_id}", :ideas_updated)
      {:noreply, assign(socket, idea: refreshed, upvoted: false)}
    else
      case Ideas.create_upvote(idea.id, voter) do
        {:ok, _} ->
          refreshed = Ideas.get_idea_by_identifier!(idea.identifier)
          Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{idea.board_id}", :ideas_updated)
          {:noreply, assign(socket, idea: refreshed, upvoted: true)}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info(:ideas_updated, socket) do
    refreshed = Ideas.get_idea_by_identifier!(socket.assigns.idea.identifier)
    {:noreply, assign(socket, idea: refreshed)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="container mx-auto max-w-3xl px-4 py-8">
        <.link href={~p"/"} class="btn btn-ghost btn-sm mb-4">&larr; Back to board</.link>

        <div class="card bg-base-100 shadow-md">
          <div class="card-body">
            <div class="flex items-start gap-6">
              <div class="flex flex-col items-center">
                <button
                  phx-click="upvote"
                  class={"btn btn-ghost btn-lg px-3 #{if @upvoted, do: "text-primary", else: "text-base-content/40"}"}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" viewBox="0 0 20 20" fill="currentColor">
                    <path
                      fill-rule="evenodd"
                      d="M14.707 12.707a1 1 0 01-1.414 0L10 9.414l-3.293 3.293a1 1 0 01-1.414-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 010 1.414z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </button>
                <span class="font-bold text-2xl">{@idea.upvote_count}</span>
              </div>
              <div class="flex-1">
                <div class="flex items-center gap-3 mb-2">
                  <span class="font-mono text-sm text-base-content/40">{@idea.identifier}</span>
                  <span class={"badge #{status_badge_class(@idea.status)}"}>{status_label(@idea.status)}</span>
                </div>
                <h1 class="text-3xl font-bold mb-4">{@idea.title}</h1>

                <%= if @idea.description do %>
                  <div class="prose max-w-none mb-4">
                    <p class="whitespace-pre-wrap">{@idea.description}</p>
                  </div>
                <% end %>

                <div class="flex items-center gap-4 text-sm text-base-content/50">
                  <div class="flex items-center gap-2">
                    <%= if @idea.submitted_by_avatar_url do %>
                      <img src={@idea.submitted_by_avatar_url} class="w-5 h-5 rounded-full" />
                    <% end %>
                    <span>{@idea.submitted_by_display_name}</span>
                  </div>
                  <span>submitted {Calendar.strftime(@idea.inserted_at, "%b %d, %Y")}</span>
                </div>

                <%= if @idea.tags != [] do %>
                  <div class="flex gap-2 mt-3">
                    <%= for tag <- @idea.tags do %>
                      <span class="badge badge-outline badge-sm">{tag}</span>
                    <% end %>
                  </div>
                <% end %>

                <%= if @idea.status == "in_progress" do %>
                  <div class="alert alert-info mt-4">
                    <span>Agent is working on this idea.</span>
                  </div>
                <% end %>

                <%= if @idea.status == "rejected" && @idea.rejection_reason do %>
                  <div class="alert alert-error mt-4">
                    <span>Rejected: {@idea.rejection_reason}</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
