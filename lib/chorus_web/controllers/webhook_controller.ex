defmodule ChorusWeb.WebhookController do
  use ChorusWeb, :controller

  require Logger

  def github(conn, params) do
    event = get_req_header(conn, "x-github-event") |> List.first()
    signature = get_req_header(conn, "x-hub-signature-256") |> List.first()

    with {:ok, secret} when secret not in [nil, ""] <- {:ok, webhook_secret()},
         {:ok, body} <- read_raw_body(conn),
         :ok <- verify_signature(body, signature, secret) do
      handle_event(event, params)
      json(conn, %{ok: true})
    else
      {:ok, nil} ->
        # No webhook secret configured — accept without verification
        handle_event(event, params)
        json(conn, %{ok: true})

      {:error, :bad_signature} ->
        conn |> put_status(401) |> json(%{error: "Invalid signature"})
    end
  end

  defp handle_event("pull_request", %{"action" => action, "pull_request" => pr, "repository" => repo}) do
    broadcast_github_activity(repo, %{
      type: "pull_request",
      action: action,
      title: pr["title"],
      number: pr["number"],
      user: pr["user"]["login"],
      url: pr["html_url"]
    })
  end

  defp handle_event("push", %{"commits" => commits, "pusher" => pusher, "repository" => repo, "ref" => ref}) do
    branch = ref |> String.replace("refs/heads/", "")
    broadcast_github_activity(repo, %{
      type: "push",
      action: "pushed",
      title: "#{length(commits)} commit(s) to #{branch}",
      user: pusher["name"],
      commits: Enum.map(Enum.take(commits, 3), &%{message: &1["message"], sha: String.slice(&1["id"], 0, 7)})
    })
  end

  defp handle_event("issues", %{"action" => action, "issue" => issue, "repository" => repo}) do
    broadcast_github_activity(repo, %{
      type: "issue",
      action: action,
      title: issue["title"],
      number: issue["number"],
      user: issue["user"]["login"],
      url: issue["html_url"]
    })
  end

  defp handle_event("issue_comment", %{"action" => "created", "comment" => comment, "issue" => issue, "repository" => repo}) do
    broadcast_github_activity(repo, %{
      type: "comment",
      action: "commented",
      title: "Comment on ##{issue["number"]}: #{issue["title"]}",
      user: comment["user"]["login"],
      url: comment["html_url"]
    })
  end

  defp handle_event(event, _params) do
    Logger.debug("Ignoring GitHub webhook event: #{event}")
  end

  defp broadcast_github_activity(repo, details) do
    repo_url = repo["html_url"]

    idea = find_idea_by_repo(repo_url)
    idea_title = if idea, do: idea.title, else: repo["full_name"]
    idea_identifier = if idea, do: idea.identifier, else: nil

    activity = %{
      event: "github_#{details.type}",
      task_title: format_github_title(details),
      idea_identifier: idea_identifier,
      idea_title: idea_title,
      branch: nil,
      last_output: details[:user],
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Chorus.PubSub, "activity:feed", {:activity, activity})

    if idea do
      Phoenix.PubSub.broadcast(Chorus.PubSub, "board:#{idea.board_id}", :ideas_updated)
    end
  end

  defp format_github_title(%{type: "pull_request", action: action, title: title, number: number}) do
    "PR ##{number} #{action}: #{title}"
  end

  defp format_github_title(%{type: "push", title: title}) do
    title
  end

  defp format_github_title(%{type: "issue", action: action, title: title, number: number}) do
    "Issue ##{number} #{action}: #{title}"
  end

  defp format_github_title(%{type: "comment", title: title}) do
    title
  end

  defp format_github_title(%{title: title}) do
    title
  end

  defp find_idea_by_repo(repo_url) do
    import Ecto.Query
    Chorus.Repo.one(
      from i in Chorus.Ideas.Idea,
        where: i.repo_url == ^repo_url,
        limit: 1
    )
  end

  defp webhook_secret do
    System.get_env("GITHUB_WEBHOOK_SECRET")
  end

  defp read_raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil -> {:ok, nil}
      body -> {:ok, body}
    end
  end

  defp verify_signature(_body, _signature, nil), do: :ok
  defp verify_signature(nil, _signature, _secret), do: :ok
  defp verify_signature(_body, nil, _secret), do: {:error, :bad_signature}

  defp verify_signature(body, "sha256=" <> hex_digest, secret) do
    computed = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(computed, hex_digest) do
      :ok
    else
      {:error, :bad_signature}
    end
  end

  defp verify_signature(_body, _signature, _secret), do: {:error, :bad_signature}
end
