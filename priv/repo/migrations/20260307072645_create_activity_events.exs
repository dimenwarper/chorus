defmodule Chorus.Repo.Migrations.CreateActivityEvents do
  use Ecto.Migration

  def change do
    create table(:activity_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event, :string, null: false
      add :title, :string
      add :detail, :string
      add :user, :string
      add :url, :string
      add :idea_id, references(:ideas, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:activity_events, [:inserted_at])
    create index(:activity_events, [:idea_id])
  end
end
