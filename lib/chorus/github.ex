defmodule Chorus.GitHub do
  @moduledoc """
  GitHub API client for repository management.
  Uses a personal access token (GITHUB_TOKEN) for server-side operations.
  """

  require Logger

  def create_repo(name, opts \\ []) do
    description = Keyword.get(opts, :description, "")
    private = Keyword.get(opts, :private, false)

    body = Jason.encode!(%{
      name: name,
      description: description,
      private: private,
      auto_init: true
    })

    case Req.post(api_url("/user/repos"),
      body: body,
      headers: headers()
    ) do
      {:ok, %{status: 201, body: resp}} ->
        {:ok, %{
          url: resp["html_url"],
          clone_url: resp["clone_url"],
          ssh_url: resp["ssh_url"],
          full_name: resp["full_name"]
        }}

      {:ok, %{status: 422, body: %{"errors" => errors}}} ->
        if Enum.any?(errors, &(&1["message"] =~ "already exists")) do
          # Repo already exists, fetch it
          owner = github_owner()
          fetch_repo(owner, name)
        else
          {:error, "GitHub API error: #{inspect(errors)}"}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "GitHub API request failed: #{inspect(reason)}"}
    end
  end

  def fetch_repo(owner, name) do
    case Req.get(api_url("/repos/#{owner}/#{name}"), headers: headers()) do
      {:ok, %{status: 200, body: resp}} ->
        {:ok, %{
          url: resp["html_url"],
          clone_url: resp["clone_url"],
          ssh_url: resp["ssh_url"],
          full_name: resp["full_name"]
        }}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "GitHub API request failed: #{inspect(reason)}"}
    end
  end

  def configured? do
    token() not in [nil, ""]
  end

  defp token do
    System.get_env("GITHUB_TOKEN")
  end

  defp github_owner do
    Application.get_env(:chorus, :github_owner) || System.get_env("GITHUB_OWNER")
  end

  defp api_url(path) do
    "https://api.github.com" <> path
  end

  defp headers do
    [
      {"authorization", "Bearer #{token()}"},
      {"accept", "application/vnd.github+json"},
      {"content-type", "application/json"},
      {"x-github-api-version", "2022-11-28"}
    ]
  end
end
