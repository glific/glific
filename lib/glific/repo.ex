defmodule Glific.Repo do
  @moduledoc """
  A repository that maps to an underlying data store, controlled by the Postgres adapter.
  """

  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres

  use ExAudit.Repo
  use Glific.RepoHelpers

  # codebeat:enable[ABC, LOC]

  @doc """
  In Join tables we rarely use the table id. We always know the object ids
  and hence more convenient to delete an entry via its object ids.
  """
  @spec delete_relationships_by_ids(atom(), {{atom(), integer}, {atom(), [integer]}}) ::
          {integer(), nil | [term()]}
  def delete_relationships_by_ids(object, fields) do
    {{key_1, value_1}, {key_2, values_2}} = fields

    object
    |> where([m], field(m, ^key_1) == ^value_1 and field(m, ^key_2) in ^values_2)
    |> __MODULE__.delete_all()
  end
end
