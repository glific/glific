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
  We use this function in most list_OBJECT api's, where we process the opts
  and the filter. Centralizing this code at the top level, to make things
  cleaner
  """
  @spec list_filter(
          map(),
          atom(),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t()),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t())
        ) :: [any]
  def list_filter(args \\ %{}, object, opts_with_fn, filter_with_fn) do
    args
    |> Enum.reduce(object, fn
      {:opts, opts}, query ->
        query
        |> opts_with_fn.(opts)
        |> limit_offset(opts)

      {:filter, filter}, query ->
        query |> filter_with_fn.(filter)

      _, query ->
        query
    end)
    |> Repo.all()
  end

  @doc """
  We use this function also  in most list_OBJECT api's, where we process the
  the filter. Centralizing this code at the top level, to make things
  cleaner
  """
  @spec count_filter(
          map(),
          atom(),
          (Ecto.Queryable.t(), %{optional(atom()) => any} -> Ecto.Queryable.t())
        ) :: integer
  def count_filter(args \\ %{}, object, filter_with_fn) do
    args
    |> Enum.reduce(object, fn
      {:filter, filter}, query ->
        query |> filter_with_fn.(filter)

      _, query ->
        query
    end)
    |> Repo.aggregate(:count)
  end

  @doc """
  Extracts the limit offset field, and adds to query
  """
  @spec limit_offset(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def limit_offset(query, opts) do
    Enum.reduce(opts, query, fn
      {:limit, limit}, query ->
        query |> limit(^limit)

      {:offset, offset}, query ->
        query |> offset(^offset)

      _, query ->
        query
    end)
  end

  @doc """
  An empty function for objects that ignore the opts
  """
  @spec opts_with_nil(any, any) :: any
  def opts_with_nil(_opts, query), do: query

  @doc """
  Need to figure out what this function does. Still learning Dataloader and its magic.
  Seems l
  ike it is not used currently, so commenting it out
  @spec data() :: Dataloader.Ecto.t()
  def data,
    do: Dataloader.Ecto.new(Repo, query: &query/2)
  """
end
