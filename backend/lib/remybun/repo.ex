defmodule Remybun.Repo do
  use Ecto.Repo,
    otp_app: :remybun,
    adapter: Ecto.Adapters.Postgres
end
