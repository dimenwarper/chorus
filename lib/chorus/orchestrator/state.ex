defmodule Chorus.Orchestrator.State do
  @moduledoc """
  In-memory orchestrator runtime state. Section 4.1.13.
  """

  defstruct [
    :config,
    :board_id,
    :prompt_template,
    running: %{},
    claimed: MapSet.new(),
    retry_attempts: %{},
    completed: MapSet.new(),
    # Recent run history for observability (kept capped)
    run_history: [],
    totals: %{
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      runtime_seconds: 0.0
    }
  ]

  def claim(%__MODULE__{} = state, idea_id) do
    %{state | claimed: MapSet.put(state.claimed, idea_id)}
  end

  def unclaim(%__MODULE__{} = state, idea_id) do
    %{state | claimed: MapSet.delete(state.claimed, idea_id)}
  end

  def add_running(%__MODULE__{} = state, idea_id, entry) do
    %{state | running: Map.put(state.running, idea_id, entry)}
  end

  def remove_running(%__MODULE__{} = state, idea_id) do
    %{state |
      running: Map.delete(state.running, idea_id),
      claimed: MapSet.delete(state.claimed, idea_id)
    }
  end

  def mark_completed(%__MODULE__{} = state, task_id, result \\ :success) do
    runner = Map.get(state.running, task_id)

    history_entry = %{
      task_id: task_id,
      identifier: runner && runner.idea && runner.idea.identifier,
      title: runner && runner.task && runner.task.title,
      result: result,
      last_output: runner && runner.last_output,
      started_at: runner && runner.started_at,
      finished_at: DateTime.utc_now()
    }

    state
    |> remove_running(task_id)
    |> Map.put(:completed, MapSet.put(state.completed, task_id))
    |> Map.update!(:run_history, fn history ->
      [history_entry | history] |> Enum.take(20)
    end)
  end

  def available_slots(%__MODULE__{} = state) do
    state.config.max_concurrent_agents - map_size(state.running)
  end

  def running?(%__MODULE__{} = state, idea_id) do
    Map.has_key?(state.running, idea_id)
  end

  def claimed?(%__MODULE__{} = state, idea_id) do
    MapSet.member?(state.claimed, idea_id)
  end

  # Retry management (Section 8.4)
  def schedule_retry(%__MODULE__{} = state, idea_id, error) do
    entry = Map.get(state.retry_attempts, idea_id, %{attempt: 0, errors: []})
    new_attempt = entry.attempt + 1

    if new_attempt > state.config.max_retries do
      # Exceeded max retries, give up
      remove_running(state, idea_id)
    else
      delay_ms = retry_delay(new_attempt)
      retry_at = DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)

      new_entry = %{
        attempt: new_attempt,
        retry_at: retry_at,
        errors: [error | entry.errors],
        idea_id: idea_id
      }

      state
      |> remove_running(idea_id)
      |> Map.put(:retry_attempts, Map.put(state.retry_attempts, idea_id, new_entry))
    end
  end

  def due_retries(%__MODULE__{} = state) do
    now = DateTime.utc_now()

    state.retry_attempts
    |> Enum.filter(fn {_id, entry} -> DateTime.compare(entry.retry_at, now) != :gt end)
    |> Enum.map(fn {id, entry} -> {id, entry} end)
  end

  def pop_retry(%__MODULE__{} = state, idea_id) do
    {entry, remaining} = Map.pop(state.retry_attempts, idea_id)
    {entry, %{state | retry_attempts: remaining}}
  end

  # Exponential backoff: 5s, 20s, 80s, 320s...
  defp retry_delay(attempt) do
    trunc(5_000 * :math.pow(4, attempt - 1))
  end
end
