defmodule Chorus.Orchestrator.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Chorus.Orchestrator.Workspace

  setup do
    root = Path.join(System.tmp_dir!(), "chorus_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "ensure_repo creates a git repo", %{root: root} do
    idea = %{identifier: "IDEA-001"}
    {:ok, path} = Workspace.ensure_repo(root, idea)

    assert File.dir?(path)
    assert File.dir?(Path.join(path, ".git"))
  end

  test "ensure_repo is idempotent", %{root: root} do
    idea = %{identifier: "IDEA-001"}
    {:ok, path1} = Workspace.ensure_repo(root, idea)
    {:ok, path2} = Workspace.ensure_repo(root, idea)

    assert path1 == path2
  end

  test "create_branch creates a git branch", %{root: root} do
    idea = %{identifier: "IDEA-002"}
    {:ok, path} = Workspace.ensure_repo(root, idea)

    assert :ok = Workspace.create_branch(path, "task/test-branch")

    {branches, 0} = System.cmd("git", ["branch"], cd: path)
    assert branches =~ "task/test-branch"
  end

  test "return_to_main switches back", %{root: root} do
    idea = %{identifier: "IDEA-003"}
    {:ok, path} = Workspace.ensure_repo(root, idea)

    Workspace.create_branch(path, "task/feature")
    Workspace.return_to_main(path)

    {branch, 0} = System.cmd("git", ["branch", "--show-current"], cd: path)
    assert String.trim(branch) in ["main", "master"]
  end

  test "clean removes workspace", %{root: root} do
    idea = %{identifier: "IDEA-004"}
    {:ok, path} = Workspace.ensure_repo(root, idea)
    assert File.dir?(path)

    Workspace.clean(root, idea)
    refute File.dir?(path)
  end
end
