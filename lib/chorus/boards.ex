defmodule Chorus.Boards do
  import Ecto.Query
  alias Chorus.Repo
  alias Chorus.Boards.Board

  def get_board!(id), do: Repo.get!(Board, id)

  def get_board(id), do: Repo.get(Board, id)

  def create_board(attrs) do
    %Board{}
    |> Board.changeset(attrs)
    |> Repo.insert()
  end

  def update_board(%Board{} = board, attrs) do
    board
    |> Board.changeset(attrs)
    |> Repo.update()
  end

  def get_board_by_owner(owner_id) do
    Repo.one(from b in Board, where: b.owner_id == ^owner_id, limit: 1)
  end

  def get_default_board do
    Repo.one(from b in Board, order_by: [asc: b.inserted_at], limit: 1)
  end
end
