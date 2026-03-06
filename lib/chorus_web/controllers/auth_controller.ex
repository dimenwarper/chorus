defmodule ChorusWeb.AuthController do
  use ChorusWeb, :controller
  plug Ueberauth

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user = %{
      "id" => to_string(auth.uid),
      "name" => auth.info.name || auth.info.nickname,
      "avatar_url" => auth.info.urls[:avatar_url] || auth.info.image,
      "provider" => to_string(auth.provider)
    }

    conn
    |> put_session("current_user", user)
    |> put_session("voter_identity", "oauth:#{auth.provider}:#{auth.uid}")
    |> put_flash(:info, "Signed in as #{user["name"]}")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    messages = Enum.map_join(failure.errors, ", ", & &1.message)

    conn
    |> put_flash(:error, "Authentication failed: #{messages}")
    |> redirect(to: ~p"/")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/")
  end
end
