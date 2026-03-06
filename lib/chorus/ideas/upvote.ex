defmodule Chorus.Ideas.Upvote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "upvotes" do
    field :voter_identity, :string

    belongs_to :idea, Chorus.Ideas.Idea

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(upvote, attrs) do
    upvote
    |> cast(attrs, [:voter_identity, :idea_id])
    |> validate_required([:voter_identity, :idea_id])
    |> unique_constraint([:idea_id, :voter_identity])
  end
end
