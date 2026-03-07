defmodule Chorus.Ideas.Approval do
  @moduledoc """
  Handles the full idea approval workflow:
  1. Transition idea to approved
  2. Create a GitHub repo for the idea
  3. Clone the repo to the local workspace
  4. Store repo_url and repo_path on the idea
  """

  require Logger

  alias Chorus.{Ideas, Repo, GitHub}
  alias Chorus.Orchestrator.Workspace

  def approve(idea_id, opts \\ []) do
    workspace_root = Keyword.get(opts, :workspace_root, ".chorus/workspaces")
    board_title = Keyword.get(opts, :board_title, "chorus")

    with {:ok, idea} <- Ideas.transition_status(idea_id, "approved"),
         {:ok, idea} <- setup_repo(idea, workspace_root, board_title) do
      {:ok, idea}
    end
  end

  defp setup_repo(idea, workspace_root, board_title) do
    if GitHub.configured?() do
      repo_name = build_repo_name(board_title, idea.title)
      description = idea.description || idea.title

      case GitHub.create_repo(repo_name, description: String.slice(description, 0, 350)) do
        {:ok, repo_info} ->
          # Register webhook for activity feed
          if repo_info[:full_name], do: GitHub.register_webhook(repo_info.full_name)

          # Clone to workspace
          case clone_repo(repo_info.clone_url, workspace_root, idea) do
            {:ok, local_path} ->
              idea
              |> Ecto.Changeset.change(repo_url: repo_info.url, repo_path: local_path)
              |> Repo.update()

            {:error, reason} ->
              Logger.error("Failed to clone repo for #{idea.identifier}: #{reason}")
              # Still save the repo_url even if clone fails
              idea
              |> Ecto.Changeset.change(repo_url: repo_info.url)
              |> Repo.update()
          end

        {:error, reason} ->
          Logger.error("Failed to create GitHub repo for #{idea.identifier}: #{reason}")
          # Fall back to local-only repo
          setup_local_repo(idea, workspace_root)
      end
    else
      Logger.info("GitHub token not configured, creating local-only repo for #{idea.identifier}")
      setup_local_repo(idea, workspace_root)
    end
  end

  defp setup_local_repo(idea, workspace_root) do
    case Workspace.ensure_repo(workspace_root, idea) do
      {:ok, path} ->
        idea
        |> Ecto.Changeset.change(repo_path: path)
        |> Repo.update()

      {:error, reason} ->
        Logger.error("Failed to create local repo for #{idea.identifier}: #{reason}")
        {:ok, idea}
    end
  end

  defp clone_repo(clone_url, workspace_root, _idea) do
    key = clone_url |> String.trim_trailing("/") |> String.trim_trailing(".git") |> String.split("/") |> List.last()
    path = Path.join(workspace_root, key) |> Path.expand()
    abs_root = Path.expand(workspace_root)

    unless String.starts_with?(path, abs_root) do
      raise "Workspace path escape detected: #{path} not under #{abs_root}"
    end

    if File.exists?(Path.join(path, ".git")) do
      {:ok, path}
    else
      File.mkdir_p!(Path.dirname(path))

      case System.cmd("git", ["clone", clone_url, path], stderr_to_stdout: true) do
        {_, 0} ->
          Logger.info("Cloned repo #{key} to #{path}")
          {:ok, path}

        {output, code} ->
          {:error, "git clone failed (exit #{code}): #{output}"}
      end
    end
  end

  defp build_repo_name(board_title, idea_title) do
    prefix = slugify(board_title)
    title = slugify(idea_title)

    "#{prefix}-#{title}"
    |> String.slice(0, 100)
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end
end
