defmodule ChorusWeb.Plugs.RawBody do
  @moduledoc """
  Caches the raw request body for webhook signature verification.
  Used as a custom body_reader for Plug.Parsers on webhook paths.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)

    conn =
      if String.starts_with?(conn.request_path, "/api/webhooks/") do
        Plug.Conn.assign(conn, :raw_body, body)
      else
        conn
      end

    {:ok, body, conn}
  end
end
