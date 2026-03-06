defmodule Chorus.Repo.Migrations.CreateUpvotes do
  use Ecto.Migration

  def change do
    create table(:upvotes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :voter_identity, :string, null: false
      add :idea_id, references(:ideas, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:upvotes, [:idea_id, :voter_identity])
    create index(:upvotes, [:idea_id])
  end
end
