defmodule Glific.Stats do
  @moduledoc """
  The stats manager and API to interface with the stat sub-system
  """

  import Ecto.Query, warn: false
  require Logger

  alias Glific.{
    Stats.Stat,
    Repo
  }

  @doc """
  Create a Stat
  """
  @spec create_stat(map()) :: {:ok, Stat.t()} | {:error, Ecto.Changeset.t()}
  def create_stat(attrs \\ %{}) do
    %Stat{}
    |> Stat.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a Stat
  """
  @spec update_stat(Stat.t(), map()) ::
          {:ok, Stat.t()} | {:error, Ecto.Changeset.t()}
  def update_stat(stat, attrs) do
    stat
    |> Stat.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the list of stats.
  Since this is very basic and only listing funcatinality we added the status filter like this.
  In future we will put the status as virtual filed in the stats itself.
  """
  @spec list_stats(map()) :: list()
  def list_stats(args),
    do: Repo.list_filter(args, Stat, &Repo.opts_with_inserted_at/2, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)
    # these filters are specific to stats only.
    # We might want to move them in the repo in the future.

    Enum.reduce(filter, query, fn
      {:period, period}, query ->
        from q in query, where: q.period == ^period

      {:hour, hour}, query ->
        from q in query, where: q.hour == ^hour

      {:date, date}, query ->
        from q in query, where: q.date == ^date

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of stats, using the same filter as list_stats
  """
  @spec count_stats(map()) :: integer
  def count_stats(args),
    do: Repo.count_filter(args, Stat, &filter_with/2)
end
