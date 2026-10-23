defmodule Keepsakes.Repo do
  use Ecto.Repo,
    otp_app: :keepsakes,
    adapter: Ecto.Adapters.Postgres
end
