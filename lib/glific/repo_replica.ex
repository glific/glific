defmodule Glific.RepoReplica do
  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres

  use Glific.RepoHelpers
end
