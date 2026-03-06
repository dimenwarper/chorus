defmodule Chorus.Orchestrator.AgentRunner do
  @moduledoc """
  Launches and manages coding agent subprocesses for tasks.
  Each task runs on its own branch in the idea's git repo.
  """

  require Logger

  alias Chorus.Orchestrator.Workspace
  alias Chorus.Workflow.Prompt

  defstruct [:task, :idea, :repo_path, :branch_name, :port, :started_at, :status, :last_output, :output_buffer]

  def start(task, idea, %{config: config, prompt_template: template, board: board}) do
    # Ensure the idea has a git repo
    case Workspace.ensure_repo(config.workspace_root, idea) do
      {:ok, repo_path} ->
        prompt =
          Prompt.render(template, %{
            idea: idea,
            attempt: task.attempt,
            board: board
          })

        # Append task-specific instructions to the prompt
        task_prompt = """
        #{prompt}

        ## Current Task

        **Task**: #{task.title}
        #{if task.description, do: "\n#{task.description}\n", else: ""}
        Work on branch `#{task.branch_name}`. Commit your changes when done.
        """

        entry = %__MODULE__{
          task: task,
          idea: idea,
          repo_path: repo_path,
          branch_name: task.branch_name,
          started_at: DateTime.utc_now(),
          status: :starting,
          last_output: nil,
          output_buffer: ""
        }

        case config.agent_command do
          nil ->
            Logger.warning("No agent command configured, dry-run for task #{task.id}")

            {:ok,
             %{entry |
               status: :dry_run,
               last_output: "Dry run — no agent command configured"
             }}

          command ->
            launch_agent(entry, command, task_prompt, repo_path, task.branch_name)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stop(%__MODULE__{port: port} = runner) when is_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        System.cmd("kill", ["-TERM", to_string(os_pid)], stderr_to_stdout: true)
      _ -> :ok
    end

    try do
      Port.close(port)
    rescue
      _ -> :ok
    end

    %{runner | status: :stopped}
  end

  def stop(runner), do: %{runner | status: :stopped}

  defp launch_agent(entry, command, prompt, repo_path, branch_name) do
    # Create the task branch
    Workspace.create_branch(repo_path, branch_name)

    # Write prompt to the repo
    prompt_path = Path.join(repo_path, ".chorus_prompt.md")
    File.write!(prompt_path, prompt)

    full_command = build_command(command, prompt_path, repo_path)

    Logger.info("Launching agent for task #{entry.task.id} on branch #{branch_name}: #{full_command}")

    try do
      port =
        Port.open({:spawn, full_command}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:line, 8192}
        ])

      {:ok, %{entry | port: port, status: :running}}
    rescue
      e ->
        Logger.error("Failed to launch agent: #{inspect(e)}")
        {:error, "Failed to launch agent: #{inspect(e)}"}
    end
  end

  defp build_command(command, prompt_path, workspace_path) do
    cond do
      String.contains?(command, "claude") ->
        "cd #{escape(workspace_path)} && cat #{escape(prompt_path)} | #{command} -p --verbose"

      true ->
        "cd #{escape(workspace_path)} && #{command} #{escape(prompt_path)}"
    end
  end

  defp escape(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end
end
