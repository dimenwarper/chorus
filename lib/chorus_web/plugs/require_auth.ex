defmodule ChorusWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires an authenticated session.
  When `admin: true` is passed, also checks ADMIN_GITHUB_ID.
  Redirects to home with an error flash if not authorized.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  def init(opts), do: opts

  def call(conn, opts) do
    case get_session(conn, "current_user") do
      nil ->
        conn
        |> put_flash(:error, "You must sign in to access this page")
        |> redirect(to: "/")
        |> halt()

      user ->
        if Keyword.get(opts, :admin, false) and not admin?(user) do
          conn
          |> put_flash(:error, "You are not authorized to access this page")
          |> redirect(to: "/")
          |> halt()
        else
          conn
        end
    end
  end

  defp admin?(user) do
    case Application.get_env(:chorus, :admin_github_id) do
      nil -> true
      "" -> true
      admin_id -> user["id"] == admin_id
    end
  end
end
