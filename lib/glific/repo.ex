defmodule Glific.Repo do
  @moduledoc """
  A repository that maps to an underlying data store, controlled by the Postgres adapter
  """
  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres
end
