defmodule Kakemono.Repo do
  use Ecto.Repo,
    otp_app: :kakemono,
    adapter: Ecto.Adapters.SQLite3
end
