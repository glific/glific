defmodule Glific.Trackers do
  @moduledoc """
  The Trackers context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Partners.Saas,
    Repo,
    Trackers.Tracker
  }

  @doc """
  Create tracker
  """
  @spec create_tracker(map()) :: {:ok, Tracker.t()} | {:error, Ecto.Changeset.t()}
  def create_tracker(attrs) do
    %Tracker{}
    |> Tracker.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update tracker
  """
  @spec update_tracker(Tracker.t(), map()) ::
          {:ok, Tracker.t()} | {:error, Ecto.Changeset.t()}
  def update_tracker(%Tracker{} = tracker, attrs) do
    tracker
    |> Tracker.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upsert tracker
  """
  @spec upsert_tracker(map(), non_neg_integer, Date.t() | nil, String.t() | nil) ::
          {:ok, Tracker.t()} | {:error, Ecto.Changeset.t()} | :ok
  def upsert_tracker(counts, organization_id, date \\ nil, period \\ "day")

  def upsert_tracker(counts, _organization_id, _date, _period) when counts == %{}, do: :ok

  def upsert_tracker(counts, organization_id, date, period) do
    date = if date == nil, do: Date.utc_today(), else: date

    attrs = %{
      counts: counts,
      organization_id: organization_id,
      date: date,
      period: period
    }

    case Repo.fetch_by(Tracker, %{date: date, period: period, organization_id: organization_id}) do
      {:ok, tracker} ->
        update_tracker(
          tracker,
          Map.put(
            attrs,
            :counts,
            Map.merge(tracker.counts, counts, fn _k, v1, v2 -> v1 + v2 end)
          )
        )

      {:error, _} ->
        {:ok, _tracker} = create_tracker(attrs)
    end
  end

  @doc """
  Resets the tracker for a given organization
  """
  @spec reset_tracker(non_neg_integer) :: any
  def reset_tracker(organization_id) do
    Tracker
    |> where([t], t.organization_id == ^organization_id)
    |> Repo.delete_all()
  end

  @doc """
  Daily summarization tasks for tracker. This also triggers monthly tasks
  at end of month
  """
  @spec daily_tasks() :: any
  def daily_tasks do
    # find the previous day
    date = Date.add(Date.utc_today(), 12)

    add_platform_day(date)

    if Date.end_of_month(date) == date do
      date
      |> Date.beginning_of_month()
      |> add_monthly_summary()
    end
  end

  # This function is called after midnight UTC to compute the stats for the platform on a daily basis
  @spec add_platform_day(Date.t()) :: any
  defp add_platform_day(date) do
    platform_id = Saas.organization_id()

    counts =
      Tracker
      |> where([t], t.date == ^date)
      |> where([t], t.period == "day")
      |> where([t], t.organization_id != ^platform_id)
      |> select([t], t.counts)
      |> Repo.all(skip_organization_id: true)
      |> daily()

    {:ok, _tracker} =
      create_tracker(%{
        date: date,
        period: "day",
        counts: counts,
        organization_id: platform_id
      })
  end

  # Given the daily totals for orgs and the platform, sum up and compute the monthly totals and store in DB
  @spec add_monthly_summary(Date.t()) :: any
  defp add_monthly_summary(date) do
    # lets go back 3 days to make sure we are in last month and use beginning of month
    Tracker
    |> where([t], fragment("date_part('year', ?)", t.date) == ^date.year)
    |> where([t], fragment("date_part('month', ?)", t.date) == ^date.month)
    |> where([t], t.period == "day")
    |> select([t], [t.counts, t.organization_id])
    |> Repo.all(skip_organization_id: true)
    |> monthly(date)
  end

  @spec daily(list()) :: map()
  defp daily([]), do: %{}

  defp daily(results) do
    results
    |> Enum.reduce(fn result, acc ->
      Map.merge(acc, result, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end

  @spec monthly(list(), Date.t()) :: list()
  defp monthly([], _month), do: []

  defp monthly(results, month) do
    results
    |> Enum.reduce(
      %{},
      fn [counts, organization_id], acc ->
        Map.put(
          acc,
          organization_id,
          Map.merge(
            Map.get(acc, organization_id, %{}),
            counts,
            fn _k, v1, v2 -> v1 + v2 end
          )
        )
      end
    )
    |> Enum.map(fn {organization_id, counts} ->
      {:ok, _tracker} =
        create_tracker(%{
          date: month,
          period: "month",
          counts: counts,
          organization_id: organization_id
        })
    end)
  end
end
