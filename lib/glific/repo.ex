defmodule Glific.Repo do
  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres
end
