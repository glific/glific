defmodule Glific.RepoReplica do
  @moduledoc """
  A read-replica repository that maps to an underlying data store, controlled by the Postgres adapter.
  """

  # In tests replica uses primary's connection pool
  dynamic_repo =
    if Application.compile_env!(:glific, :environment) == :test do
      Glific.Repo
    else
      __MODULE__
    end

  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres,
    default_dynamic_repo: dynamic_repo,
    read_only: true

  use Glific.RepoHelpers
end
