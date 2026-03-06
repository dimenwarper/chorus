defmodule Chorus.Orchestrator.DispatcherTest do
  use ExUnit.Case, async: true

  alias Chorus.Orchestrator.{Dispatcher, State}
  alias Chorus.Workflow.Config

  defp make_idea(overrides) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        identifier: "IDEA-001",
        title: "Test Idea",
        status: "approved",
        priority: nil,
        upvote_count: 0,
        approved_at: ~U[2026-01-01 00:00:00Z],
        inserted_at: ~U[2026-01-01 00:00:00Z]
      },
      overrides
    )
  end

  defp make_state(mode \\ :manual, max_agents \\ 3) do
    %State{
      config: %Config{dispatch_priority_mode: mode, max_concurrent_agents: max_agents},
      board_id: "board-1",
      prompt_template: ""
    }
  end

  describe "select_candidates/2" do
    test "filters out non-eligible ideas" do
      ideas = [
        make_idea(%{identifier: "IDEA-001", status: "approved"}),
        make_idea(%{identifier: "IDEA-002", status: "pending"}),
        make_idea(%{identifier: "IDEA-003", status: "rejected"})
      ]

      candidates = Dispatcher.select_candidates(ideas, make_state())
      assert length(candidates) == 1
      assert hd(candidates).identifier == "IDEA-001"
    end

    test "respects available slots" do
      ideas =
        for i <- 1..5 do
          make_idea(%{identifier: "IDEA-#{String.pad_leading("#{i}", 3, "0")}", status: "approved"})
        end

      candidates = Dispatcher.select_candidates(ideas, make_state(:manual, 2))
      assert length(candidates) == 2
    end

    test "excludes already running ideas" do
      idea = make_idea(%{status: "approved"})
      state = make_state() |> State.add_running(idea.id, %{})

      candidates = Dispatcher.select_candidates([idea], state)
      assert candidates == []
    end
  end

  describe "manual priority sorting" do
    test "sorts by priority ascending, null last" do
      ideas = [
        make_idea(%{identifier: "IDEA-003", priority: nil}),
        make_idea(%{identifier: "IDEA-001", priority: 1}),
        make_idea(%{identifier: "IDEA-002", priority: 5})
      ]

      candidates = Dispatcher.select_candidates(ideas, make_state(:manual))
      identifiers = Enum.map(candidates, & &1.identifier)

      assert identifiers == ["IDEA-001", "IDEA-002", "IDEA-003"]
    end
  end

  describe "upvotes priority sorting" do
    test "sorts by upvote_count descending" do
      ideas = [
        make_idea(%{identifier: "IDEA-001", upvote_count: 3}),
        make_idea(%{identifier: "IDEA-002", upvote_count: 10}),
        make_idea(%{identifier: "IDEA-003", upvote_count: 7})
      ]

      candidates = Dispatcher.select_candidates(ideas, make_state(:upvotes))
      identifiers = Enum.map(candidates, & &1.identifier)

      assert identifiers == ["IDEA-002", "IDEA-003", "IDEA-001"]
    end
  end

  describe "hybrid priority sorting" do
    test "produces composite score from priority and upvotes" do
      ideas = [
        make_idea(%{identifier: "IDEA-001", priority: 1, upvote_count: 1}),
        make_idea(%{identifier: "IDEA-002", priority: 3, upvote_count: 10}),
        make_idea(%{identifier: "IDEA-003", priority: 2, upvote_count: 5})
      ]

      candidates = Dispatcher.select_candidates(ideas, make_state(:hybrid))
      identifiers = Enum.map(candidates, & &1.identifier)

      # IDEA-001: p_rank=1, u_rank=3 -> 1*0.7 + 3*0.3 = 1.6
      # IDEA-002: p_rank=3, u_rank=1 -> 3*0.7 + 1*0.3 = 2.4
      # IDEA-003: p_rank=2, u_rank=2 -> 2*0.7 + 2*0.3 = 2.0
      assert identifiers == ["IDEA-001", "IDEA-003", "IDEA-002"]
    end
  end
end
