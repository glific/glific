defmodule Glific.Repo do
  @moduledoc """
  A repository that maps to an underlying data store, controlled by the Postgres adapter.

  We add a few functions to make our life easier with a few helper functions that ecto does
  not provide.
  """

  alias __MODULE__

  import Ecto.Query

  use Ecto.Repo,
    otp_app: :glific,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Glific version of get, which returns a tuple with an :ok | :error as the first element
  """
  @spec fetch(Ecto.Queryable.t(), term(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, [String.t()]}
  def fetch(queryable, id, opts \\ []) do
    case get(queryable, id, opts) do
      nil -> {:error, ["#{queryable} #{id}", "Resource not found"]}
      resource -> {:ok, resource}
    end
  end

  @doc """
  Glific version of get_by, which returns a tuple with an :ok | :error as the first element
  """
  @spec fetch_by(Ecto.Queryable.t(), Keyword.t() | map(), Keyword.t()) ::
          {atom(), Ecto.Schema.t() | String.t()}
  def fetch_by(queryable, clauses, opts \\ []) do
    case get_by(queryable, clauses, opts) do
      nil -> {:error, "Resource not found"}
      resource -> {:ok, resource}
    end
  end

  @doc """
  Get map of label to ids for easier lookup for various system objects - language, tag
  """
  @spec label_id_map(Ecto.Queryable.t(), [String.t()]) :: %{String.t() => integer}
  def label_id_map(queryable, labels) do
    queryable
    |> where([q], q.label in ^labels)
    |> select([:id, :label])
    |> Repo.all()
    |> Enum.reduce(%{}, fn tag, acc -> Map.put(acc, tag.label, tag.id) end)
  end

  @doc """
  Need to figure out what this function does. Still learning Dataloader and its magic.
  Seems like it is not used currently, so commenting it out
  @spec data() :: Dataloader.Ecto.t()
  def data,
    do: Dataloader.Ecto.new(Repo, query: &query/2)
  """
end
