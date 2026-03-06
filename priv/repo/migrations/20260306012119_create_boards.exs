defmodule Chorus.Repo.Migrations.CreateBoards do
  use Ecto.Migration

  def change do
    create table(:boards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :owner_id, :string, null: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end
  end
end
