defmodule Chorus.Repo.Migrations.CreateIdeas do
  use Ecto.Migration

  def change do
    create table(:ideas, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identifier, :string, null: false
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "pending"
      add :priority, :integer
      add :upvote_count, :integer, null: false, default: 0
      add :tags, {:array, :string}, default: []
      add :admin_notes, :text
      add :rejection_reason, :text
      add :approved_at, :utc_datetime
      add :resolved_at, :utc_datetime

      add :submitted_by_user_id, :string, null: false
      add :submitted_by_provider, :string, null: false
      add :submitted_by_display_name, :string, null: false
      add :submitted_by_avatar_url, :string

      add :board_id, references(:boards, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ideas, [:identifier])
    create index(:ideas, [:board_id])
    create index(:ideas, [:status])
    create index(:ideas, [:board_id, :status])
  end
end
