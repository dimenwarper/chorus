defmodule Chorus.Ideas.Idea do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved in_progress completed rejected archived)

  # Valid state transitions per Section 4.1.4
  @transitions %{
    "pending" => ~w(approved rejected),
    "approved" => ~w(in_progress archived),
    "in_progress" => ~w(completed approved archived),
    "completed" => ~w(archived),
    "rejected" => ~w(pending archived)
  }

  schema "ideas" do
    field :identifier, :string
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :priority, :integer
    field :upvote_count, :integer, default: 0
    field :tags, {:array, :string}, default: []
    field :admin_notes, :string
    field :rejection_reason, :string
    field :approved_at, :utc_datetime
    field :resolved_at, :utc_datetime

    # Embedded submitter identity (Section 4.1.5)
    field :submitted_by_user_id, :string
    field :submitted_by_provider, :string
    field :submitted_by_display_name, :string
    field :submitted_by_avatar_url, :string

    field :repo_path, :string

    belongs_to :board, Chorus.Boards.Board
    has_many :upvotes, Chorus.Ideas.Upvote
    has_many :tasks, Chorus.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def transitions, do: @transitions

  def create_changeset(idea, attrs) do
    idea
    |> cast(attrs, [
      :title,
      :description,
      :tags,
      :submitted_by_user_id,
      :submitted_by_provider,
      :submitted_by_display_name,
      :submitted_by_avatar_url,
      :board_id
    ])
    |> validate_required([
      :title,
      :submitted_by_user_id,
      :submitted_by_provider,
      :submitted_by_display_name,
      :board_id
    ])
    |> validate_length(:title, min: 5, max: 200)
    |> validate_length(:description, max: 10_000)
    |> validate_length(:tags, max: 5)
    |> validate_tag_lengths()
    |> put_change(:status, "pending")
  end

  def admin_changeset(idea, attrs) do
    idea
    |> cast(attrs, [:title, :description, :priority, :tags, :admin_notes, :status, :rejection_reason])
    |> maybe_validate_transition(idea)
  end

  def status_changeset(idea, new_status) do
    idea
    |> change(status: new_status)
    |> validate_transition(idea.status, new_status)
    |> maybe_set_timestamps(new_status)
  end

  defp validate_transition(changeset, from, to) do
    allowed = Map.get(@transitions, from, [])

    if to in allowed do
      changeset
    else
      add_error(changeset, :status, "cannot transition from #{from} to #{to}")
    end
  end

  defp maybe_validate_transition(changeset, idea) do
    case get_change(changeset, :status) do
      nil -> changeset
      new_status -> validate_transition(changeset, idea.status, new_status)
    end
  end

  defp maybe_set_timestamps(changeset, "approved"),
    do: put_change(changeset, :approved_at, DateTime.utc_now() |> DateTime.truncate(:second))

  defp maybe_set_timestamps(changeset, status) when status in ~w(completed archived),
    do: put_change(changeset, :resolved_at, DateTime.utc_now() |> DateTime.truncate(:second))

  defp maybe_set_timestamps(changeset, _), do: changeset

  defp validate_tag_lengths(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags ->
        if Enum.all?(tags, &(String.length(&1) <= 30)) do
          changeset
        else
          add_error(changeset, :tags, "each tag must be at most 30 characters")
        end
    end
  end
end
