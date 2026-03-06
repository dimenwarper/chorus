defmodule Chorus.Workflow.Prompt do
  @moduledoc """
  Renders the prompt template with idea context. Section 12.
  """

  def render(template, %{idea: idea, attempt: attempt, board: board}) do
    template
    |> String.replace("{{idea.identifier}}", idea.identifier || "")
    |> String.replace("{{idea.title}}", idea.title || "")
    |> String.replace("{{idea.description}}", idea.description || "")
    |> String.replace("{{idea.status}}", idea.status || "")
    |> String.replace("{{idea.tags}}", Enum.join(idea.tags || [], ", "))
    |> String.replace("{{idea.priority}}", to_string(idea.priority || ""))
    |> String.replace("{{attempt}}", to_string(attempt || "first"))
    |> String.replace("{{board.title}}", board.title || "")
    |> String.replace("{{board.description}}", board.description || "")
  end
end
