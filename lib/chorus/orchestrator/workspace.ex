defmodule Chorus.Orchestrator.Workspace do
  @moduledoc """
  Per-idea git repo management. Section 9.
  Each idea gets a persistent git repo. Tasks run on branches.
  """

  require Logger

  def ensure_repo(root, idea) do
    key = sanitize_key(idea.identifier)
    path = Path.join(root, key) |> Path.expand()
    abs_root = Path.expand(root)

    unless String.starts_with?(path, abs_root) do
      raise "Workspace path escape detected: #{path} not under #{abs_root}"
    end

    if File.exists?(Path.join(path, ".git")) do
      {:ok, path}
    else
      File.mkdir_p!(path)

      case System.cmd("git", ["init"], cd: path, stderr_to_stdout: true) do
        {_, 0} ->
          # Create initial commit so branches work
          System.cmd("git", ["commit", "--allow-empty", "-m", "Initialize idea repo"], cd: path, stderr_to_stdout: true)
          Logger.info("Initialized git repo for #{idea.identifier} at #{path}")
          {:ok, path}

        {output, code} ->
          {:error, "git init failed (exit #{code}): #{output}"}
      end
    end
  end

  def create_branch(repo_path, branch_name) do
    # Create branch from main/master
    case System.cmd("git", ["checkout", "-b", branch_name], cd: repo_path, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _} ->
        # Branch might already exist, try switching to it
        case System.cmd("git", ["checkout", branch_name], cd: repo_path, stderr_to_stdout: true) do
          {_, 0} -> :ok
          {output2, _code} -> {:error, "Failed to create/switch to branch #{branch_name}: #{output} / #{output2}"}
        end
    end
  end

  def return_to_main(repo_path) do
    # Try main first, then master
    case System.cmd("git", ["checkout", "main"], cd: repo_path, stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> System.cmd("git", ["checkout", "master"], cd: repo_path, stderr_to_stdout: true); :ok
    end
  end

  def clean(root, idea) do
    key = sanitize_key(idea.identifier)
    path = Path.join(root, key) |> Path.expand()
    abs_root = Path.expand(root)

    if String.starts_with?(path, abs_root) and File.exists?(path) do
      File.rm_rf!(path)
      :ok
    else
      :noop
    end
  end

  def clean_by_key(root, workspace_key) do
    path = Path.join(root, workspace_key) |> Path.expand()
    abs_root = Path.expand(root)

    if String.starts_with?(path, abs_root) and File.exists?(path) do
      File.rm_rf!(path)
      :ok
    else
      :noop
    end
  end

  def sanitize_key(identifier) do
    String.replace(identifier, ~r/[^A-Za-z0-9._-]/, "_")
  end
end
