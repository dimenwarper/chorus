defmodule ChorusWeb.Api.AdminController do
  use ChorusWeb, :controller

  alias Chorus.{Boards, Ideas}

  def review_queue(conn, _params) do
    board = Boards.get_default_board()
    pending = if board, do: Ideas.list_pending_ideas(board.id), else: []
    json(conn, %{ideas: Enum.map(pending, &serialize_idea/1)})
  end

  def batch_review(conn, %{"actions" => actions}) do
    parsed =
      Enum.map(actions, fn a ->
        %{
          idea_id: a["idea_id"],
          action: a["action"],
          priority: a["priority"],
          tags: a["tags"],
          reason: a["reason"]
        }
      end)

    results = Ideas.batch_review(parsed)

    response =
      Enum.map(results, fn
        {:ok, idea} -> %{idea_id: idea.id, status: "ok"}
        {:error, idea_id, reason} -> %{idea_id: idea_id, status: "error", reason: inspect(reason)}
      end)

    json(conn, %{results: response})
  end

  def update_idea(conn, %{"id" => idea_id} = params) do
    changes =
      params
      |> Map.take(["title", "description", "priority", "tags", "status", "admin_notes", "rejection_reason"])
      |> Enum.into(%{}, fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Ideas.update_idea(idea_id, changes) do
      {:ok, idea} -> json(conn, %{idea: serialize_idea(idea)})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: Chorus.Helpers.changeset_errors(changeset)})
    end
  end

  def board_settings(conn, _params) do
    board = Boards.get_default_board()
    json(conn, %{board: %{id: board.id, title: board.title, description: board.description, settings: board.settings}})
  end

  def update_board_settings(conn, params) do
    board = Boards.get_default_board()

    changes =
      params
      |> Map.take(["title", "description", "settings"])
      |> Enum.into(%{}, fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Boards.update_board(board, changes) do
      {:ok, board} -> json(conn, %{board: %{id: board.id, title: board.title, description: board.description, settings: board.settings}})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: Chorus.Helpers.changeset_errors(changeset)})
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
      created_at: idea.inserted_at
    }
  end
end
