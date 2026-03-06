defmodule ChorusWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires an authenticated session.
  Redirects to home with an error flash if not signed in.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "current_user") do
      conn
    else
      conn
      |> put_flash(:error, "You must sign in to access this page")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
