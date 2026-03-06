defmodule Chorus.WorkflowTest do
  use ExUnit.Case, async: true

  alias Chorus.Workflow.{Loader, Config, Prompt}

  describe "Loader.parse/1" do
    test "parses YAML front matter and prompt body" do
      content = """
      ---
      board:
        title: Test Board
        dispatch_priority_mode: hybrid
      polling:
        interval_ms: 10000
      agent:
        max_concurrent: 3
      ---

      # Hello {{idea.title}}

      Work on this idea.
      """

      {:ok, workflow} = Loader.parse(content)

      assert workflow.config["board"]["title"] == "Test Board"
      assert workflow.config["polling"]["interval_ms"] == 10_000
      assert workflow.prompt_template =~ "Hello {{idea.title}}"
    end

    test "handles content with no front matter" do
      {:ok, workflow} = Loader.parse("Just a prompt template")

      assert workflow.config == %{}
      assert workflow.prompt_template == "Just a prompt template"
    end

    test "returns error for invalid YAML" do
      content = """
      ---
      invalid: [unterminated
      ---
      body
      """

      assert {:error, _} = Loader.parse(content)
    end
  end

  describe "Config.from_workflow/1" do
    test "extracts typed config with defaults" do
      workflow = %{
        config: %{
          "board" => %{"dispatch_priority_mode" => "upvotes"},
          "polling" => %{"interval_ms" => 5000},
          "agent" => %{"max_concurrent" => 4, "max_retries" => 5}
        }
      }

      config = Config.from_workflow(workflow)

      assert config.dispatch_priority_mode == :upvotes
      assert config.poll_interval_ms == 5000
      assert config.max_concurrent_agents == 4
      assert config.max_retries == 5
      # defaults
      assert config.priority_weight == 0.7
      assert config.workspace_root == ".chorus/workspaces"
    end

    test "applies defaults for empty config" do
      config = Config.from_workflow(%{config: %{}})

      assert config.dispatch_priority_mode == :manual
      assert config.poll_interval_ms == 30_000
      assert config.max_concurrent_agents == 1
    end

    test "resolves $ENV{} patterns" do
      System.put_env("CHORUS_TEST_VAR", "resolved_value")

      workflow = %{
        config: %{
          "workspace" => %{"root" => "/tmp/$ENV{CHORUS_TEST_VAR}/workspaces"}
        }
      }

      config = Config.from_workflow(workflow)
      assert config.workspace_root == "/tmp/resolved_value/workspaces"

      System.delete_env("CHORUS_TEST_VAR")
    end
  end

  describe "Config.validate/1" do
    test "valid config passes" do
      config = Config.from_workflow(%{config: %{}})
      assert :ok = Config.validate(config)
    end

    test "invalid poll interval fails" do
      config = %Config{poll_interval_ms: -1, max_concurrent_agents: 1, max_retries: 3}
      assert {:error, errors} = Config.validate(config)
      assert Keyword.has_key?(errors, :poll_interval_ms)
    end
  end

  describe "Prompt.render/2" do
    test "substitutes template variables" do
      template = "Work on {{idea.identifier}}: {{idea.title}} for {{board.title}}"

      idea = %{
        identifier: "IDEA-001",
        title: "Test Idea",
        description: "A description",
        status: "approved",
        tags: ["ml", "test"],
        priority: 1
      }

      board = %{title: "ML Board", description: "A board"}

      result = Prompt.render(template, %{idea: idea, attempt: nil, board: board})

      assert result == "Work on IDEA-001: Test Idea for ML Board"
    end

    test "handles nil values gracefully" do
      template = "{{idea.description}} attempt {{attempt}}"

      idea = %{
        identifier: "IDEA-001",
        title: "Test",
        description: nil,
        status: "approved",
        tags: [],
        priority: nil
      }

      result = Prompt.render(template, %{idea: idea, attempt: 2, board: %{title: "", description: ""}})
      assert result == " attempt 2"
    end
  end
end
