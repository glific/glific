defmodule GlificWeb.Schema.Helpers do
  @moduledoc """
  Helper functions that interface between the needs of our GraphQL code and the database.

  Most likely we will move this function to Glific.repo
  """

  @doc """
  Given a query and a list of ids, return a map of the data retrieved from the DB that match the ids
  """
  @spec by_id(Ecto.Queryable.t(), [integer]) :: %{required(integer) => Ecto.Schema.t()}
  def by_id(model, ids) do
    import Ecto.Query

    ids = ids |> Enum.uniq()

    model
    |> where([m], m.id in ^ids)
    |> Glific.Repo.all()
    |> Map.new(&{&1.id, &1})
  end
end
