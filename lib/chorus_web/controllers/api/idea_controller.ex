defmodule ChorusWeb.Api.IdeaController do
  use ChorusWeb, :controller

  alias Chorus.{Boards, Ideas}

  def index(conn, _params) do
    board = Boards.get_default_board()
    ideas = if board, do: Ideas.list_visible_ideas(board.id), else: []
    json(conn, %{ideas: Enum.map(ideas, &serialize_idea/1)})
  end

  def show(conn, %{"identifier" => identifier}) do
    idea = Ideas.get_idea_by_identifier!(identifier)
    json(conn, %{idea: serialize_idea(idea)})
  end

  def create(conn, %{"title" => _} = params) do
    board = Boards.get_default_board()
    user = get_session(conn, "current_user")

    attrs = %{
      title: params["title"],
      description: params["description"],
      tags: params["tags"] || [],
      submitted_by_user_id: user["id"],
      submitted_by_provider: "github",
      submitted_by_display_name: user["name"],
      submitted_by_avatar_url: user["avatar_url"],
      board_id: board.id
    }

    case Ideas.create_idea(attrs) do
      {:ok, idea} ->
        Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{board.id}", :ideas_updated)
        conn |> put_status(:created) |> json(%{idea: serialize_idea(idea)})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: Chorus.Helpers.changeset_errors(changeset)})
    end
  end

  def upvote(conn, %{"id" => idea_id}) do
    voter = get_session(conn, "voter_identity") || "anon:session:#{conn.remote_ip |> :inet.ntoa() |> to_string()}"

    case Ideas.create_upvote(idea_id, voter) do
      {:ok, result} -> json(conn, result)
      {:error, :not_upvotable} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "Cannot upvote this idea"})
      {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "Upvote failed"})
    end
  end

  def remove_upvote(conn, %{"id" => idea_id}) do
    voter = get_session(conn, "voter_identity") || "anon:session:#{conn.remote_ip |> :inet.ntoa() |> to_string()}"

    case Ideas.delete_upvote(idea_id, voter) do
      {:ok, result} -> json(conn, result)
    end
  end

  defp serialize_idea(idea) do
    %{
      id: idea.id,
      identifier: idea.identifier,
      title: idea.title,
      description: idea.description,
      status: idea.status,
      priority: idea.priority,
      upvote_count: idea.upvote_count,
      tags: idea.tags,
      submitted_by: %{
        display_name: idea.submitted_by_display_name,
        avatar_url: idea.submitted_by_avatar_url
      },
      created_at: idea.inserted_at,
      approved_at: idea.approved_at
    }
  end
end
