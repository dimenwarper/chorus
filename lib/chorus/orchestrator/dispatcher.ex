defmodule Chorus.Orchestrator.Dispatcher do
  @moduledoc """
  Candidate selection and sorting logic. Section 8.2.
  """

  alias Chorus.Orchestrator.State

  def select_candidates(ideas, %State{} = state) do
    ideas
    |> Enum.filter(&eligible?(&1, state))
    |> sort_by_priority(state.config.dispatch_priority_mode)
    |> Enum.take(State.available_slots(state))
  end

  defp eligible?(idea, state) do
    has_required_fields?(idea) and
      idea.status in ["approved", "in_progress"] and
      not State.running?(state, idea.id) and
      not State.claimed?(state, idea.id)
  end

  defp has_required_fields?(idea) do
    idea.id != nil and idea.identifier != nil and idea.title != nil and idea.status != nil
  end

  # Section 8.2: manual mode
  defp sort_by_priority(ideas, :manual) do
    Enum.sort_by(ideas, fn idea ->
      {priority_sort_key(idea.priority), idea.approved_at || idea.inserted_at, idea.identifier}
    end)
  end

  # Section 8.2: upvotes mode
  defp sort_by_priority(ideas, :upvotes) do
    Enum.sort_by(ideas, fn idea ->
      {-idea.upvote_count, idea.approved_at || idea.inserted_at, idea.identifier}
    end)
  end

  # Section 8.2: hybrid mode
  defp sort_by_priority(ideas, :hybrid) do
    # Rank-based composite score
    by_priority = ideas |> Enum.sort_by(&priority_sort_key(&1.priority)) |> rank()
    by_upvotes = ideas |> Enum.sort_by(&(-&1.upvote_count)) |> rank()

    Enum.sort_by(ideas, fn idea ->
      p_rank = Map.get(by_priority, idea.id, 999)
      u_rank = Map.get(by_upvotes, idea.id, 999)
      score = p_rank * 0.7 + u_rank * 0.3
      {score, idea.approved_at || idea.inserted_at, idea.identifier}
    end)
  end

  # null priority sorts last (higher number = lower priority)
  defp priority_sort_key(nil), do: 999_999
  defp priority_sort_key(p), do: p

  defp rank(sorted_ideas) do
    sorted_ideas
    |> Enum.with_index(1)
    |> Map.new(fn {idea, idx} -> {idea.id, idx} end)
  end
end
