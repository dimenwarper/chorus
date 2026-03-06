defmodule Chorus.Orchestrator.Server do
  @moduledoc """
  The orchestrator GenServer. Owns the poll tick, dispatches agent tasks,
  handles reconciliation and retries. Tasks are the unit of dispatch.
  """

  use GenServer
  require Logger

  alias Chorus.{Ideas, Boards, Tasks}
  alias Chorus.Orchestrator.{State, AgentRunner, Workspace}
  alias Chorus.Workflow.{Loader, Config}

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  def reload_workflow do
    GenServer.call(__MODULE__, :reload_workflow)
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    workflow_path = Keyword.get(opts, :workflow_path)

    case load_workflow(workflow_path) do
      {:ok, config, prompt_template} ->
        board = Boards.get_default_board()

        state = %State{
          config: config,
          board_id: board && board.id,
          prompt_template: prompt_template
        }

        Logger.info("Orchestrator started (poll=#{config.poll_interval_ms}ms, max_agents=#{config.max_concurrent_agents})")
        schedule_tick(config.poll_interval_ms)
        {:ok, state}

      {:error, reason} ->
        Logger.warning("Orchestrator starting without workflow: #{reason}")

        state = %State{
          config: %Config{},
          board_id: nil,
          prompt_template: ""
        }

        schedule_tick(30_000)
        {:ok, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    state = tick(state)
    schedule_tick(state.config.poll_interval_ms)
    {:noreply, state}
  end

  def handle_info({port, {:data, {:eol, line}}}, state) when is_port(port) do
    state = handle_agent_output(state, port, line)
    {:noreply, state}
  end

  def handle_info({port, {:data, {:noeol, line}}}, state) when is_port(port) do
    state = handle_agent_output(state, port, line)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, exit_code}}, state) when is_port(port) do
    state = handle_agent_exit(state, port, exit_code)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:status, _from, state) do
    summary = %{
      running: map_size(state.running),
      claimed: MapSet.size(state.claimed),
      retry_queue: map_size(state.retry_attempts),
      completed: MapSet.size(state.completed),
      available_slots: State.available_slots(state),
      config: %{
        poll_interval_ms: state.config.poll_interval_ms,
        max_concurrent_agents: state.config.max_concurrent_agents,
        dispatch_priority_mode: state.config.dispatch_priority_mode
      },
      running_tasks:
        Enum.map(state.running, fn {task_id, runner} ->
          %{
            task_id: task_id,
            task_title: runner.task.title,
            idea_identifier: runner.idea.identifier,
            idea_title: runner.idea.title,
            branch: runner.branch_name,
            status: runner.status,
            started_at: runner.started_at,
            last_output: runner.last_output
          }
        end),
      run_history: state.run_history
    }

    {:reply, summary, state}
  end

  def handle_call(:reload_workflow, _from, state) do
    case load_workflow(nil) do
      {:ok, config, prompt_template} ->
        Logger.info("Workflow reloaded")
        {:reply, :ok, %{state | config: config, prompt_template: prompt_template}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Poll tick
  # ---------------------------------------------------------------------------

  defp tick(state) do
    if is_nil(state.board_id) do
      case Boards.get_default_board() do
        nil -> state
        board -> %{state | board_id: board.id}
      end
    else
      state
      |> reconcile()
      |> process_retries()
      |> dispatch_pending_tasks()
    end
  end

  # Reconcile: check running tasks are still valid
  defp reconcile(state) do
    if map_size(state.running) == 0 do
      state
    else
      Enum.reduce(Map.keys(state.running), state, fn task_id, acc ->
        runner = Map.get(acc.running, task_id)

        if stalled?(runner, acc.config.stall_timeout_ms) do
          Logger.warning("Task #{task_id} appears stalled, stopping")
          AgentRunner.stop(runner)
          Tasks.fail_task(task_id, "stall timeout")
          broadcast_activity(acc, runner, "stalled")
          State.schedule_retry(acc, task_id, "stall timeout")
        else
          acc
        end
      end)
    end
  end

  # Process due retries
  defp process_retries(state) do
    due = State.due_retries(state)

    Enum.reduce(due, state, fn {task_id, _entry}, acc ->
      {retry_entry, acc} = State.pop_retry(acc, task_id)
      Logger.info("Retrying task #{task_id} (attempt #{retry_entry.attempt})")
      dispatch_task(acc, task_id)
    end)
  end

  # Dispatch pending tasks
  defp dispatch_pending_tasks(state) do
    if State.available_slots(state) <= 0 do
      state
    else
      pending = Tasks.fetch_pending_tasks()

      pending
      |> Enum.reject(fn task -> State.running?(state, task.id) or State.claimed?(state, task.id) end)
      |> Enum.take(State.available_slots(state))
      |> Enum.reduce(state, fn task, acc ->
        if State.available_slots(acc) > 0 do
          dispatch_task(acc, task.id)
        else
          acc
        end
      end)
    end
  end

  defp dispatch_task(state, task_id) do
    task = Tasks.get_task!(task_id)
    idea = Ideas.get_idea!(task.idea_id)
    board = Boards.get_board!(state.board_id)

    # Start the task (sets branch name, status=running)
    {:ok, task} = Tasks.start_task(task_id)

    # Transition idea to in_progress if it's approved
    if idea.status == "approved" do
      Ideas.transition_status(idea.id, "in_progress")
    end

    state = State.claim(state, task_id)

    case AgentRunner.start(task, idea, %{
           config: state.config,
           prompt_template: state.prompt_template,
           board: board
         }) do
      {:ok, runner} ->
        Logger.info("Dispatched task #{task.title} for #{idea.identifier} on branch #{task.branch_name}")
        broadcast_activity(state, runner, "started")
        State.add_running(state, task_id, runner)

      {:error, reason} ->
        Logger.error("Failed to dispatch task #{task_id}: #{reason}")
        Tasks.fail_task(task_id, reason)
        State.schedule_retry(state, task_id, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Agent subprocess handling
  # ---------------------------------------------------------------------------

  defp handle_agent_output(state, port, line) do
    case find_runner_by_port(state, port) do
      {task_id, runner} ->
        updated = %{runner |
          last_output: line,
          output_buffer: (runner.output_buffer || "") <> line <> "\n"
        }
        broadcast_activity(state, updated, "working")
        State.add_running(state, task_id, updated)

      nil ->
        state
    end
  end

  defp handle_agent_exit(state, port, exit_code) do
    case find_runner_by_port(state, port) do
      {task_id, runner} ->
        # Return to main branch
        Workspace.return_to_main(runner.repo_path)

        if exit_code == 0 do
          Logger.info("Task completed successfully: #{runner.task.title}")
          output = runner.output_buffer || runner.last_output || ""
          Tasks.complete_task(task_id, output)
          broadcast_activity(state, runner, "completed")
          Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{state.board_id}", :ideas_updated)
          State.mark_completed(state, task_id, :success)
        else
          Logger.warning("Task failed: #{runner.task.title} (exit #{exit_code})")
          Tasks.fail_task(task_id, "exit code #{exit_code}")
          broadcast_activity(state, runner, "failed")
          State.schedule_retry(state, task_id, "exit code #{exit_code}")
        end

      nil ->
        state
    end
  end

  defp find_runner_by_port(state, port) do
    Enum.find(state.running, fn {_id, runner} -> runner.port == port end)
    |> case do
      {id, runner} -> {id, runner}
      nil -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Activity broadcasting for the live feed
  # ---------------------------------------------------------------------------

  defp broadcast_activity(_state, runner, event) do
    activity = %{
      event: event,
      task_title: runner.task && runner.task.title,
      idea_identifier: runner.idea && runner.idea.identifier,
      idea_title: runner.idea && runner.idea.title,
      branch: runner.branch_name,
      last_output: runner.last_output,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Chorus.PubSub, "activity:feed", {:activity, activity})
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end

  defp stalled?(nil, _), do: false

  defp stalled?(runner, timeout_ms) do
    elapsed = DateTime.diff(DateTime.utc_now(), runner.started_at, :millisecond)
    elapsed > timeout_ms
  end

  defp load_workflow(path) do
    case Loader.load(path) do
      {:ok, workflow} ->
        config = Config.from_workflow(workflow)

        case Config.validate(config) do
          :ok -> {:ok, config, workflow.prompt_template}
          {:error, errors} -> {:error, "Config validation failed: #{inspect(errors)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
