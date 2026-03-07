defmodule Chorus.Tasks do
  @moduledoc """
  Context for managing tasks within ideas.
  Tasks are the units of work dispatched to agents.
  """

  import Ecto.Query
  alias Chorus.Repo
  alias Chorus.Tasks.Task

  def get_task!(id), do: Repo.get!(Task, id)

  def list_tasks(idea_id) do
    from(t in Task,
      where: t.idea_id == ^idea_id,
      order_by: [asc: t.inserted_at]
    )
    |> Repo.all()
  end

  def create_task(attrs) do
    %Task{}
    |> Task.create_changeset(attrs)
    |> Repo.insert()
  end

  def start_task(task_id) do
    task = get_task!(task_id)

    task
    |> Task.start_changeset()
    |> Repo.update()
  end

  def complete_task(task_id, output, opts \\ []) do
    task = get_task!(task_id)

    task
    |> Task.complete_changeset(output, opts)
    |> Repo.update()
  end

  def fail_task(task_id, error) do
    task = get_task!(task_id)

    task
    |> Task.fail_changeset(error)
    |> Repo.update()
  end

  def cancel_task(task_id) do
    task = get_task!(task_id)

    task
    |> Task.cancel_changeset()
    |> Repo.update()
  end

  def fetch_pending_tasks do
    from(t in Task,
      where: t.status == "pending",
      preload: [:idea],
      order_by: [asc: t.inserted_at]
    )
    |> Repo.all()
  end

  def fetch_running_tasks do
    from(t in Task,
      where: t.status == "running",
      preload: [:idea],
      order_by: [asc: t.started_at]
    )
    |> Repo.all()
  end

  def count_by_status(idea_id) do
    from(t in Task,
      where: t.idea_id == ^idea_id,
      group_by: t.status,
      select: {t.status, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def list_all_tasks_grouped do
    from(t in Task,
      preload: [:idea],
      order_by: [asc: t.inserted_at]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.status)
  end

  def recent_activity(limit \\ 20) do
    tasks =
      from(t in Task,
        where: t.status in ["running", "completed", "failed"],
        preload: [:idea],
        order_by: [desc: t.updated_at],
        limit: ^limit
      )
      |> Repo.all()

    events =
      from(e in Chorus.ActivityEvent,
        preload: [:idea],
        order_by: [desc: e.inserted_at],
        limit: ^limit
      )
      |> Repo.all()
      |> Enum.map(fn e ->
        %{
          event: e.event,
          task_title: e.title,
          idea_identifier: e.idea && e.idea.identifier,
          idea_title: e.idea && e.idea.title,
          branch: nil,
          last_output: e.detail,
          summary: e.summary,
          timestamp: e.inserted_at
        }
      end)

    # Merge and sort by time, take limit
    (tasks ++ events)
    |> Enum.sort_by(fn
      %{timestamp: t} -> t
      %{updated_at: t} -> t
    end, {:desc, DateTime})
    |> Enum.take(limit)
  end
end
