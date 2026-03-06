defmodule Chorus.Boards.Board do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "boards" do
    field :title, :string
    field :description, :string
    field :owner_id, :string
    field :settings, :map, default: %{}

    has_many :ideas, Chorus.Ideas.Idea

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(title owner_id)a
  @optional_fields ~w(description settings)a

  def changeset(board, attrs) do
    board
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  # Typed access to settings with defaults (Section 4.1.2)
  def upvote_weight_enabled?(%__MODULE__{settings: s}),
    do: Map.get(s, "upvote_weight_enabled", false)

  def upvote_weight_factor(%__MODULE__{settings: s}),
    do: Map.get(s, "upvote_weight_factor", 1.0)

  def require_oauth_to_upvote?(%__MODULE__{settings: s}),
    do: Map.get(s, "require_oauth_to_upvote", false)

  def anonymous_upvote_strategy(%__MODULE__{settings: s}),
    do: Map.get(s, "anonymous_upvote_strategy", "fingerprint")

  def allowed_oauth_providers(%__MODULE__{settings: s}),
    do: Map.get(s, "allowed_oauth_providers", ["github"])

  def max_pending_ideas_per_user(%__MODULE__{settings: s}),
    do: Map.get(s, "max_pending_ideas_per_user", 10)
end
