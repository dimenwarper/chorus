defmodule Chorus.Repo.Migrations.AddSummaryToActivityEvents do
  use Ecto.Migration

  def up do
    columns =
      repo().query!("PRAGMA table_info(activity_events)")
      |> Map.get(:rows)
      |> Enum.map(fn [_, name | _] -> name end)

    unless "summary" in columns do
      alter table(:activity_events) do
        add :summary, :string
      end
    end
  end

  def down do
    alter table(:activity_events) do
      remove :summary
    end
  end
end
