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
    summary = (pr["body"] || "") |> String.slice(0, 200) |> String.split("\n") |> List.first("")
    broadcast_github_activity(repo, %{
      type: "pull_request",
      action: action,
      title: pr["title"],
      number: pr["number"],
      user: pr["user"]["login"],
      url: pr["html_url"],
      summary: summary
    })
  end

  defp handle_event("push", %{"commits" => commits, "pusher" => pusher, "repository" => repo, "ref" => ref}) do
    branch = ref |> String.replace("refs/heads/", "")
    summary = commits |> Enum.take(3) |> Enum.map_join("\n", fn c -> "#{String.slice(c["id"], 0, 7)} #{c["message"] |> String.split("\n") |> List.first()}" end)
    broadcast_github_activity(repo, %{
      type: "push",
      action: "pushed",
      title: "#{length(commits)} commit(s) to #{branch}",
      user: pusher["name"],
      summary: summary
    })
  end

  defp handle_event("issues", %{"action" => action, "issue" => issue, "repository" => repo}) do
    summary = (issue["body"] || "") |> String.slice(0, 200) |> String.split("\n") |> List.first("")
    broadcast_github_activity(repo, %{
      type: "issue",
      action: action,
      title: issue["title"],
      number: issue["number"],
      user: issue["user"]["login"],
      url: issue["html_url"],
      summary: summary
    })
  end

  defp handle_event("issue_comment", %{"action" => "created", "comment" => comment, "issue" => issue, "repository" => repo}) do
    summary = (comment["body"] || "") |> String.slice(0, 200) |> String.split("\n") |> List.first("")
    broadcast_github_activity(repo, %{
      type: "comment",
      action: "commented",
      title: "Comment on ##{issue["number"]}: #{issue["title"]}",
      user: comment["user"]["login"],
      url: comment["html_url"],
      summary: summary
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
    event_name = "github_#{details.type}"
    title = format_github_title(details)

    summary = details[:summary] || ""
    summary = if summary != "", do: String.slice(summary, 0, 200), else: nil

    # Persist to DB
    Chorus.Repo.insert!(%Chorus.ActivityEvent{
      event: event_name,
      title: title,
      detail: details[:user],
      url: details[:url],
      idea_id: if(idea, do: idea.id),
      summary: summary
    })

    # Broadcast for live updates
    activity = %{
      event: event_name,
      task_title: title,
      idea_identifier: idea_identifier,
      idea_title: idea_title,
      branch: nil,
      last_output: details[:user],
      summary: summary,
      timestamp: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Chorus.PubSub, "activity:feed", {:activity, activity})

    if idea do
      if idea.status == "approved" do
        Chorus.Ideas.transition_status(idea.id, "in_progress")
      end

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
