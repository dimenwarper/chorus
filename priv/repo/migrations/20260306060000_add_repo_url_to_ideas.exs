defmodule Chorus.Repo.Migrations.AddRepoUrlToIdeas do
  use Ecto.Migration

  def change do
    alter table(:ideas) do
      add :repo_url, :string
    end
  end
end
