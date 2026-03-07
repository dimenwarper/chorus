defmodule Chorus.ActivityEvent do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activity_events" do
    field :event, :string
    field :title, :string
    field :detail, :string
    field :user, :string
    field :url, :string

    belongs_to :idea, Chorus.Ideas.Idea

    timestamps(type: :utc_datetime)
  end
end
