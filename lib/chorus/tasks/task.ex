defmodule Chorus.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending running completed failed cancelled)

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :branch_name, :string
    field :agent_output, :string
    field :pr_url, :string
    field :error, :string
    field :attempt, :integer, default: 0
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :idea, Chorus.Ideas.Idea

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def create_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :idea_id])
    |> validate_required([:title, :idea_id])
    |> validate_length(:title, min: 3, max: 500)
    |> put_change(:status, "pending")
  end

  def start_changeset(task) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    branch = "task/#{task.id |> String.slice(0, 8)}-#{slugify(task.title)}"

    task
    |> change(status: "running", started_at: now, branch_name: branch, attempt: (task.attempt || 0) + 1)
  end

  def complete_changeset(task, output, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    pr_url = Keyword.get(opts, :pr_url)

    changes = %{status: "completed", completed_at: now, agent_output: output}
    changes = if pr_url, do: Map.put(changes, :pr_url, pr_url), else: changes

    task
    |> change(changes)
  end

  def fail_changeset(task, error) do
    task
    |> change(status: "failed", error: error)
  end

  def cancel_changeset(task) do
    task
    |> change(status: "cancelled")
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 40)
  end
end
