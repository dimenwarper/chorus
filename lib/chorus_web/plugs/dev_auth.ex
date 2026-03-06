defmodule ChorusWeb.Plugs.DevAuth do
  @moduledoc """
  Development-only plug that simulates an authenticated user.
  Only activates when GITHUB_CLIENT_ID is not set, allowing
  local development without OAuth credentials.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if oauth_configured?() do
      # Real OAuth is configured, don't auto-login
      conn
    else
      if get_session(conn, "current_user") do
        conn
      else
        user = %{
          "id" => "dev-user-1",
          "name" => "Dev User",
          "avatar_url" => nil,
          "provider" => "github"
        }

        conn
        |> put_session("current_user", user)
        |> put_session("voter_identity", "oauth:github:dev-user-1")
      end
    end
  end

  defp oauth_configured? do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, [])
    config[:client_id] not in [nil, ""]
  end
end
