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

  def register_webhook(repo_full_name) do
    webhook_url = webhook_url()
    secret = System.get_env("GITHUB_WEBHOOK_SECRET")

    if webhook_url do
      body = Jason.encode!(%{
        name: "web",
        active: true,
        events: ["push", "pull_request", "issues", "issue_comment"],
        config: %{
          url: webhook_url,
          content_type: "json",
          secret: secret || "",
          insecure_ssl: "0"
        }
      })

      case Req.post(api_url("/repos/#{repo_full_name}/hooks"),
        body: body,
        headers: headers()
      ) do
        {:ok, %{status: 201}} ->
          Logger.info("Webhook registered for #{repo_full_name}")
          :ok

        {:ok, %{status: 422}} ->
          Logger.info("Webhook already exists for #{repo_full_name}")
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Failed to register webhook for #{repo_full_name}: #{status} #{inspect(body)}")
          {:error, "webhook registration failed: #{status}"}

        {:error, reason} ->
          Logger.warning("Failed to register webhook for #{repo_full_name}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.debug("No PHX_HOST configured, skipping webhook registration")
      :ok
    end
  end

  def create_pull_request(repo_full_name, branch, title, body \\ "") do
    payload = Jason.encode!(%{
      title: title,
      head: branch,
      base: "main",
      body: body
    })

    case Req.post(api_url("/repos/#{repo_full_name}/pulls"),
      body: payload,
      headers: headers()
    ) do
      {:ok, %{status: 201, body: resp}} ->
        {:ok, resp["html_url"]}

      {:ok, %{status: 422, body: %{"errors" => errors}}} ->
        # Could be "no commits between base and head" or PR already exists
        Logger.warning("PR creation returned 422 for #{repo_full_name}: #{inspect(errors)}")
        {:error, "PR creation failed: #{inspect(errors)}"}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("PR creation failed for #{repo_full_name}: #{status}")
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

  defp webhook_url do
    case System.get_env("PHX_HOST") do
      nil -> nil
      "" -> nil
      host -> "https://#{host}/api/webhooks/github"
    end
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
