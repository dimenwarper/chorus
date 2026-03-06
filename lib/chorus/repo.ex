defmodule Chorus.Repo do
  use Ecto.Repo,
    otp_app: :chorus,
    adapter: Ecto.Adapters.SQLite3
end
