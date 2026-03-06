defmodule Chorus.Workflow.Config do
  @moduledoc """
  Typed getters for workflow config values with defaults
  and environment variable resolution. Section 6.3.
  """

  defstruct [
    # Board config (6.3.1)
    board_title: nil,
    board_description: nil,
    dispatch_priority_mode: :manual,
    priority_weight: 0.7,
    upvote_weight: 0.3,
    upvote_weight_enabled: false,
    upvote_weight_factor: 1.0,
    # Polling (6.3.3)
    poll_interval_ms: 30_000,
    # Workspace (6.3.4)
    workspace_root: ".chorus/workspaces",
    # Hooks (6.3.5)
    hooks: %{},
    # Agent (6.3.6)
    agent_command: nil,
    max_concurrent_agents: 1,
    max_retries: 3,
    stall_timeout_ms: 300_000,
    # Raw config map
    raw: %{}
  ]

  def from_workflow(%{config: raw}) do
    board = Map.get(raw, "board", %{})
    polling = Map.get(raw, "polling", %{})
    workspace = Map.get(raw, "workspace", %{})
    hooks = Map.get(raw, "hooks", %{})
    agent = Map.get(raw, "agent", %{})
    codex = Map.get(raw, "codex", %{})

    %__MODULE__{
      board_title: resolve(Map.get(board, "title")),
      board_description: resolve(Map.get(board, "description")),
      dispatch_priority_mode: parse_priority_mode(Map.get(board, "dispatch_priority_mode", "manual")),
      priority_weight: Map.get(board, "priority_weight", 0.7) |> to_float(),
      upvote_weight: Map.get(board, "upvote_weight", 0.3) |> to_float(),
      upvote_weight_enabled: Map.get(board, "upvote_weight_enabled", false),
      upvote_weight_factor: Map.get(board, "upvote_weight_factor", 1.0) |> to_float(),
      poll_interval_ms: Map.get(polling, "interval_ms", 30_000),
      workspace_root: resolve(Map.get(workspace, "root", ".chorus/workspaces")),
      hooks: hooks,
      agent_command: resolve(Map.get(agent, "command") || Map.get(codex, "command")),
      max_concurrent_agents: Map.get(agent, "max_concurrent", 1),
      max_retries: Map.get(agent, "max_retries", 3),
      stall_timeout_ms: Map.get(agent, "stall_timeout_ms", 300_000),
      raw: raw
    }
  end

  def validate(%__MODULE__{} = config) do
    errors =
      []
      |> validate_positive(:poll_interval_ms, config.poll_interval_ms)
      |> validate_positive(:max_concurrent_agents, config.max_concurrent_agents)
      |> validate_positive(:max_retries, config.max_retries)
      |> validate_priority_mode(config.dispatch_priority_mode)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # Resolve $ENV{VAR_NAME} patterns
  defp resolve(nil), do: nil

  defp resolve(value) when is_binary(value) do
    Regex.replace(~r/\$ENV\{(\w+)\}/, value, fn _, var ->
      System.get_env(var) || ""
    end)
  end

  defp resolve(value), do: value

  defp parse_priority_mode("manual"), do: :manual
  defp parse_priority_mode("upvotes"), do: :upvotes
  defp parse_priority_mode("hybrid"), do: :hybrid
  defp parse_priority_mode(_), do: :manual

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1
  defp to_float(_), do: 0.0

  defp validate_positive(errors, _field, value) when is_integer(value) and value > 0, do: errors
  defp validate_positive(errors, field, _), do: [{field, "must be a positive integer"} | errors]

  defp validate_priority_mode(errors, mode) when mode in [:manual, :upvotes, :hybrid], do: errors
  defp validate_priority_mode(errors, _), do: [{:dispatch_priority_mode, "must be manual, upvotes, or hybrid"} | errors]
end
