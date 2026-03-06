defmodule ChorusWeb.Plugs.AssignUser do
  @moduledoc """
  LiveView on_mount hook that assigns current_user from session.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    {:cont, assign(socket, current_user: session["current_user"])}
  end

  def on_mount(:require_auth, _params, session, socket) do
    case session["current_user"] do
      nil ->
        {:halt, socket |> put_flash(:error, "You must sign in") |> redirect(to: "/")}

      user ->
        {:cont, assign(socket, current_user: user)}
    end
  end
end
