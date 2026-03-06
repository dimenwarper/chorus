defmodule Chorus.IdeasTest do
  use Chorus.DataCase, async: true

  alias Chorus.Ideas
  alias Chorus.Boards

  setup do
    {:ok, board} =
      Boards.create_board(%{title: "Test Board", owner_id: "github:user:1"})

    %{board: board}
  end

  defp idea_attrs(board, overrides \\ %{}) do
    Map.merge(
      %{
        title: "A test idea proposal",
        description: "Some description",
        tags: ["test"],
        submitted_by_user_id: "user1",
        submitted_by_provider: "github",
        submitted_by_display_name: "Test User",
        board_id: board.id
      },
      overrides
    )
  end

  describe "create_idea/1" do
    test "creates an idea with auto-generated identifier", %{board: board} do
      {:ok, idea} = Ideas.create_idea(idea_attrs(board))

      assert idea.identifier == "IDEA-001"
      assert idea.status == "pending"
      assert idea.upvote_count == 0
    end

    test "generates sequential identifiers", %{board: board} do
      {:ok, _} = Ideas.create_idea(idea_attrs(board))
      {:ok, idea2} = Ideas.create_idea(idea_attrs(board, %{title: "Second idea here"}))

      assert idea2.identifier == "IDEA-002"
    end

    test "validates title length", %{board: board} do
      {:error, changeset} = Ideas.create_idea(idea_attrs(board, %{title: "Hi"}))
      assert errors_on(changeset).title
    end

    test "validates max 5 tags", %{board: board} do
      {:error, changeset} =
        Ideas.create_idea(idea_attrs(board, %{tags: ~w(a b c d e f)}))

      assert errors_on(changeset).tags
    end
  end

  describe "status transitions" do
    setup %{board: board} do
      {:ok, idea} = Ideas.create_idea(idea_attrs(board))
      %{idea: idea}
    end

    test "pending -> approved", %{idea: idea} do
      {:ok, updated} = Ideas.transition_status(idea.id, "approved")
      assert updated.status == "approved"
      assert updated.approved_at
    end

    test "pending -> rejected", %{idea: idea} do
      {:ok, updated} = Ideas.transition_status(idea.id, "rejected")
      assert updated.status == "rejected"
    end

    test "pending -> in_progress is invalid", %{idea: idea} do
      {:error, changeset} = Ideas.transition_status(idea.id, "in_progress")
      assert errors_on(changeset).status
    end

    test "approved -> in_progress", %{idea: idea} do
      {:ok, approved} = Ideas.transition_status(idea.id, "approved")
      {:ok, updated} = Ideas.transition_status(approved.id, "in_progress")
      assert updated.status == "in_progress"
    end

    test "in_progress -> completed", %{idea: idea} do
      {:ok, approved} = Ideas.transition_status(idea.id, "approved")
      {:ok, in_prog} = Ideas.transition_status(approved.id, "in_progress")
      {:ok, updated} = Ideas.transition_status(in_prog.id, "completed")
      assert updated.status == "completed"
      assert updated.resolved_at
    end

    test "rejected -> pending (reconsider)", %{idea: idea} do
      {:ok, rejected} = Ideas.transition_status(idea.id, "rejected")
      {:ok, updated} = Ideas.transition_status(rejected.id, "pending")
      assert updated.status == "pending"
    end
  end

  describe "upvotes" do
    setup %{board: board} do
      {:ok, idea} = Ideas.create_idea(idea_attrs(board))
      %{idea: idea}
    end

    test "create_upvote increments count", %{idea: idea} do
      {:ok, %{count: 1}} = Ideas.create_upvote(idea.id, "oauth:github:user1")
      assert Ideas.get_upvote_count(idea.id) == 1
    end

    test "duplicate upvote is idempotent", %{idea: idea} do
      {:ok, %{count: 1}} = Ideas.create_upvote(idea.id, "oauth:github:user1")
      {:ok, %{count: 1}} = Ideas.create_upvote(idea.id, "oauth:github:user1")
      assert Ideas.get_upvote_count(idea.id) == 1
    end

    test "different voters each count", %{idea: idea} do
      {:ok, _} = Ideas.create_upvote(idea.id, "oauth:github:user1")
      {:ok, %{count: 2}} = Ideas.create_upvote(idea.id, "oauth:github:user2")
      assert Ideas.get_upvote_count(idea.id) == 2
    end

    test "delete_upvote decrements count", %{idea: idea} do
      {:ok, _} = Ideas.create_upvote(idea.id, "oauth:github:user1")
      {:ok, %{upvoted: false, count: 0}} = Ideas.delete_upvote(idea.id, "oauth:github:user1")
      assert Ideas.get_upvote_count(idea.id) == 0
    end

    test "delete non-existent upvote is a no-op", %{idea: idea} do
      {:ok, %{upvoted: false, count: 0}} = Ideas.delete_upvote(idea.id, "oauth:github:nobody")
    end

    test "has_upvoted? returns correct state", %{idea: idea} do
      refute Ideas.has_upvoted?(idea.id, "oauth:github:user1")
      {:ok, _} = Ideas.create_upvote(idea.id, "oauth:github:user1")
      assert Ideas.has_upvoted?(idea.id, "oauth:github:user1")
    end

    test "cannot upvote rejected ideas", %{idea: idea} do
      {:ok, rejected} = Ideas.transition_status(idea.id, "rejected")
      assert {:error, :not_upvotable} = Ideas.create_upvote(rejected.id, "oauth:github:user1")
    end

    test "cannot upvote archived ideas", %{idea: idea} do
      {:ok, approved} = Ideas.transition_status(idea.id, "approved")
      {:ok, archived} = Ideas.transition_status(approved.id, "archived")
      assert {:error, :not_upvotable} = Ideas.create_upvote(archived.id, "oauth:github:user1")
    end
  end

  describe "batch_review/1" do
    test "approves and rejects in batch", %{board: board} do
      {:ok, idea1} = Ideas.create_idea(idea_attrs(board, %{title: "First idea to review"}))
      {:ok, idea2} = Ideas.create_idea(idea_attrs(board, %{title: "Second idea to review"}))

      results =
        Ideas.batch_review([
          %{idea_id: idea1.id, action: "approve", priority: 1, tags: ["infra"]},
          %{idea_id: idea2.id, action: "reject", reason: "Out of scope"}
        ])

      assert [{:ok, approved}, {:ok, rejected}] = results
      assert approved.status == "approved"
      assert approved.priority == 1
      assert approved.tags == ["infra"]
      assert rejected.status == "rejected"
      assert rejected.rejection_reason == "Out of scope"
    end

    test "skips non-pending ideas with error", %{board: board} do
      {:ok, idea} = Ideas.create_idea(idea_attrs(board))
      {:ok, _} = Ideas.transition_status(idea.id, "approved")

      [result] = Ideas.batch_review([%{idea_id: idea.id, action: "approve"}])
      idea_id = idea.id
      assert {:error, ^idea_id, msg} = result
      assert msg =~ "not in pending status"
    end
  end

  describe "fetch_candidate_ideas/0" do
    test "returns only approved and in_progress ideas", %{board: board} do
      {:ok, idea1} = Ideas.create_idea(idea_attrs(board, %{title: "Pending idea stays here"}))
      {:ok, idea2} = Ideas.create_idea(idea_attrs(board, %{title: "This one gets approved"}))
      {:ok, _} = Ideas.transition_status(idea2.id, "approved")

      candidates = Ideas.fetch_candidate_ideas()
      ids = Enum.map(candidates, & &1.id)

      refute idea1.id in ids
      assert idea2.id in ids
    end
  end

  describe "list_visible_ideas/1" do
    test "excludes archived ideas", %{board: board} do
      {:ok, idea} = Ideas.create_idea(idea_attrs(board))
      {:ok, approved} = Ideas.transition_status(idea.id, "approved")
      {:ok, _archived} = Ideas.transition_status(approved.id, "archived")

      visible = Ideas.list_visible_ideas(board.id)
      assert Enum.empty?(visible)
    end
  end

  describe "count_pending_ideas_by_user/2" do
    test "counts only pending ideas for the given user", %{board: board} do
      {:ok, _} = Ideas.create_idea(idea_attrs(board))
      {:ok, idea2} = Ideas.create_idea(idea_attrs(board, %{title: "Second pending idea"}))
      {:ok, _} = Ideas.transition_status(idea2.id, "approved")

      assert Ideas.count_pending_ideas_by_user(board.id, "user1") == 1
    end
  end
end
