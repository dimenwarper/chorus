defmodule Chorus.Workflow.Loader do
  @moduledoc """
  Reads and parses WORKFLOW.md files.
  Returns {config, prompt_template} per Section 6.2.
  """

  @default_path "WORKFLOW.md"

  def load(path \\ nil) do
    path = path || System.get_env("CHORUS_WORKFLOW_PATH") || @default_path

    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, "Cannot read #{path}: #{reason}"}
    end
  end

  def parse(content) do
    case split_front_matter(content) do
      {:ok, yaml_str, body} ->
        case YamlElixir.read_from_string(yaml_str) do
          {:ok, config} when is_map(config) ->
            {:ok, %{config: config, prompt_template: String.trim(body)}}

          {:ok, _} ->
            {:error, "Front matter must be a YAML mapping"}

          {:error, reason} ->
            {:error, "Invalid YAML front matter: #{inspect(reason)}"}
        end

      :no_front_matter ->
        {:ok, %{config: %{}, prompt_template: String.trim(content)}}
    end
  end

  defp split_front_matter(content) do
    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      ["", yaml, body] -> {:ok, yaml, body}
      ["" | [yaml | [body | _]]] -> {:ok, yaml, body}
      _ -> :no_front_matter
    end
  end
end
