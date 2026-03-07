defmodule Chorus.Ideas do
  @moduledoc """
  The Idea Store — primary data source for the board UI, admin interface,
  and orchestrator dispatch. Implements Section 11.1 operations.
  """

  import Ecto.Query
  alias Chorus.Repo
  alias Chorus.Ideas.{Idea, Upvote}
  alias Ecto.Multi

  # ---------------------------------------------------------------------------
  # Idea CRUD
  # ---------------------------------------------------------------------------

  def get_idea!(id), do: Repo.get!(Idea, id)

  def get_idea_by_identifier!(identifier) do
    Repo.get_by!(Idea, identifier: identifier)
  end

  def create_idea(attrs) do
    Multi.new()
    |> Multi.run(:identifier, fn repo, _changes ->
      next = next_identifier(repo, attrs[:board_id] || attrs["board_id"])
      {:ok, next}
    end)
    |> Multi.insert(:idea, fn %{identifier: identifier} ->
      %Idea{}
      |> Idea.create_changeset(attrs)
      |> Ecto.Changeset.put_change(:identifier, identifier)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{idea: idea}} -> {:ok, idea}
      {:error, :idea, changeset, _} -> {:error, changeset}
    end
  end

  defp next_identifier(repo, board_id) do
    count =
      repo.one(from i in Idea, where: i.board_id == ^board_id, select: count(i.id))

    "IDEA-#{String.pad_leading(to_string(count + 1), 3, "0")}"
  end

  def update_idea(idea_id, changes) when is_map(changes) do
    idea = get_idea!(idea_id)

    idea
    |> Idea.admin_changeset(changes)
    |> Repo.update()
  end

  def transition_status(idea_id, new_status) do
    idea = get_idea!(idea_id)

    idea
    |> Idea.status_changeset(new_status)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Queries for orchestrator dispatch (Section 11.1)
  # ---------------------------------------------------------------------------

  def fetch_candidate_ideas do
    from(i in Idea,
      where: i.status in ["approved", "in_progress"]
    )
    |> Repo.all()
  end

  def fetch_ideas_by_statuses(statuses) when is_list(statuses) do
    from(i in Idea, where: i.status in ^statuses)
    |> Repo.all()
  end

  def fetch_idea_statuses_by_ids(idea_ids) when is_list(idea_ids) do
    from(i in Idea,
      where: i.id in ^idea_ids,
      select: {i.id, i.status}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Listing for board UI
  # ---------------------------------------------------------------------------

  def list_visible_ideas(board_id) do
    from(i in Idea,
      where: i.board_id == ^board_id and i.status in ["approved", "in_progress", "completed"],
      order_by: [
        asc:
          fragment(
            "CASE ? WHEN 'in_progress' THEN 0 WHEN 'approved' THEN 1 WHEN 'completed' THEN 2 ELSE 3 END",
            i.status
          ),
        desc: i.upvote_count,
        asc: i.inserted_at
      ]
    )
    |> Repo.all()
  end

  def list_all_ideas(board_id) do
    from(i in Idea,
      where: i.board_id == ^board_id and i.status not in ["archived"],
      order_by: [
        asc:
          fragment(
            "CASE ? WHEN 'in_progress' THEN 0 WHEN 'approved' THEN 1 WHEN 'pending' THEN 2 WHEN 'completed' THEN 3 WHEN 'rejected' THEN 4 ELSE 5 END",
            i.status
          ),
        desc: i.upvote_count,
        asc: i.inserted_at
      ]
    )
    |> Repo.all()
  end

  def list_pending_ideas(board_id) do
    from(i in Idea,
      where: i.board_id == ^board_id and i.status == "pending",
      order_by: [asc: i.inserted_at]
    )
    |> Repo.all()
  end

  def count_pending_ideas_by_user(board_id, user_id) do
    from(i in Idea,
      where:
        i.board_id == ^board_id and
          i.status == "pending" and
          i.submitted_by_user_id == ^user_id,
      select: count(i.id)
    )
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Batch review (Section 5.2.2)
  # ---------------------------------------------------------------------------

  def batch_review(actions) when is_list(actions) do
    Enum.map(actions, fn action ->
      idea = get_idea!(action.idea_id)

      if idea.status != "pending" do
        {:error, action.idea_id, "idea is not in pending status (current: #{idea.status})"}
      else
        case action.action do
          "approve" ->
            changes =
              %{status: "approved"}
              |> maybe_put(:priority, action[:priority])
              |> maybe_put(:tags, action[:tags])

            case update_idea_with_transition(idea, changes, "approved") do
              {:ok, idea} -> {:ok, idea}
              {:error, changeset} -> {:error, action.idea_id, changeset}
            end

          "reject" ->
            changes =
              %{status: "rejected"}
              |> maybe_put(:rejection_reason, action[:reason])

            case update_idea_with_transition(idea, changes, "rejected") do
              {:ok, idea} -> {:ok, idea}
              {:error, changeset} -> {:error, action.idea_id, changeset}
            end

          other ->
            {:error, action.idea_id, "unknown action: #{other}"}
        end
      end
    end)
  end

  defp update_idea_with_transition(idea, changes, new_status) do
    idea
    |> Idea.admin_changeset(Map.delete(changes, :status))
    |> Ecto.Changeset.put_change(:status, new_status)
    |> maybe_put_timestamp(new_status)
    |> Repo.update()
  end

  defp maybe_put_timestamp(changeset, "approved"),
    do: Ecto.Changeset.put_change(changeset, :approved_at, DateTime.utc_now() |> DateTime.truncate(:second))

  defp maybe_put_timestamp(changeset, _), do: changeset

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
  # Upvotes (Section 11.1 operations 6-9)
  # ---------------------------------------------------------------------------

  @non_upvotable_statuses ~w(rejected archived)

  def create_upvote(idea_id, voter_identity) do
    idea = get_idea!(idea_id)

    if idea.status in @non_upvotable_statuses do
      {:error, :not_upvotable}
    else
      %Upvote{}
      |> Upvote.changeset(%{idea_id: idea_id, voter_identity: voter_identity})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:idea_id, :voter_identity])
      |> case do
        {:ok, _upvote} ->
          update_upvote_count(idea_id)

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def delete_upvote(idea_id, voter_identity) do
    case Repo.one(
           from(u in Upvote,
             where: u.idea_id == ^idea_id and u.voter_identity == ^voter_identity
           )
         ) do
      nil ->
        count = get_upvote_count(idea_id)
        {:ok, %{upvoted: false, count: count}}

      upvote ->
        Repo.delete!(upvote)
        count = get_upvote_count(idea_id)

        from(i in Idea, where: i.id == ^idea_id)
        |> Repo.update_all(set: [upvote_count: count])

        {:ok, %{upvoted: false, count: count}}
    end
  end

  def get_upvote_count(idea_id) do
    Repo.one(from u in Upvote, where: u.idea_id == ^idea_id, select: count(u.id))
  end

  def has_upvoted?(idea_id, voter_identity) do
    Repo.exists?(
      from(u in Upvote,
        where: u.idea_id == ^idea_id and u.voter_identity == ^voter_identity
      )
    )
  end

  defp update_upvote_count(idea_id) do
    count = get_upvote_count(idea_id)

    from(i in Idea, where: i.id == ^idea_id)
    |> Repo.update_all(set: [upvote_count: count])

    {:ok, %{upvoted: true, count: count}}
  end
end
