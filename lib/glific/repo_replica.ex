defmodule Glific.RepoReplica do
  @moduledoc """
  A read-replica repository that maps to an underlying data store, controlled by the Postgres adapter.
  """

  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres

  # TODO: if we are adding `read_only: true`, then RepoHelpers can't have delete fn, so we need
  # to figure out a way to not add the function in that case, for now its fine. 
  use Glific.RepoHelpers
end
