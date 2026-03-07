defmodule Chorus.Repo.Migrations.AddSummaryToActivityEvents do
  use Ecto.Migration

  def change do
    alter table(:activity_events) do
      add :summary, :string
    end
  end
end
