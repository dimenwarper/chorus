defmodule Chorus.Repo.Migrations.AddPrUrlToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :pr_url, :string
    end
  end
end
