defmodule ChorusWeb.Plugs.DevAuth do
  @moduledoc """
  Development-only plug that simulates an authenticated user.
  Sets a test user in the session so LiveViews can access it.
  In production, this would be replaced by real OAuth.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "current_user") do
      conn
    else
      user = %{
        "id" => "dev-user-1",
        "name" => "Dev User",
        "avatar_url" => nil
      }

      conn
      |> put_session("current_user", user)
      |> put_session("voter_identity", "oauth:github:dev-user-1")
    end
  end
end
