defmodule Chorus.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "pending"
      add :branch_name, :string
      add :agent_output, :text
      add :error, :text
      add :attempt, :integer, default: 0
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :idea_id, references(:ideas, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:idea_id])
    create index(:tasks, [:idea_id, :status])

    # Add repo_path to ideas for tracking the git repo location
    alter table(:ideas) do
      add :repo_path, :string
    end
  end
end
