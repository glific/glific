defmodule Glific.Trackers.Tracker do
  @moduledoc """
  The tracker object
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  @required_fields [:organization_id, :counts]
  @optional_fields [:day, :month]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          counts: map() | %{},
          day: Date.t() | nil,
          month: Date.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "trackers" do
    field(:day, :date)
    field(:month, :date)
    field(:counts, :map, default: %{})

    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Tracker.t(), map()) :: Ecto.Changeset.t()
  def changeset(tracker, attrs) do
    tracker
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

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
  @spec upsert_tracker(map(), non_neg_integer, Date.t() | nil) ::
          {:ok, Tracker.t()} | {:error, Ecto.Changeset.t()}
  def upsert_tracker(counts, organization_id, day \\ nil) do
    day = if day == nil, do: Date.utc_today(), else: day

    attrs = %{
      counts: counts,
      organization_id: organization_id,
      day: day
    }

    case Repo.fetch_by(Tracker, %{day: day, organization_id: organization_id}) do
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
  Resets the tracker for a given flow in a month (optional_
  """
  @spec reset_tracker(non_neg_integer, non_neg_integer) :: any
  def reset_tracker(organization_id, month \\ 0) do
    Tracker
    |> where([t], t.organization_id == ^organization_id)
    |> add_month(month)
    |> Repo.delete_all()
  end

  @spec add_month(Ecto.Query.t(), non_neg_integer) :: Ecto.Query.t()
  defp add_month(query, 0), do: query

  defp add_month(query, month),
    do:
      query
      |> where([t], t.month == ^month)

  @doc """
  This function is called after midnite UTC to compute the stats for
  the platform on a daily basis
  """
  @spec add_platform_day() :: any
  def add_platform_day() do
    # find the previous day
    day = Date.add(Date.utc_today(), -1)

    platform_id = Glific.Partners.Saas.organization_id()

    counts =
      Tracker
      |> where([t], t.day == ^day)
      |> where([t], is_nil(t.month))
      |> where([t], t.organization_id != ^platform_id)
      |> select([t], t.counts)
      |> Repo.all(skip_organization_id: true)
      |> daily()

    {:ok, _tracker} =
      create_tracker(%{
        day: day,
        counts: counts,
        organization_id: platform_id
      })
  end

  def add_monthly_summary() do
    # lets go back 3 days to make sure we are in last month and use beginning of month
    day =
      Date.utc_today()
      |> Date.add(-3)
      |> Date.beginning_of_month()

    Tracker
    |> where([t], fragment("date_part('year', ?)", t.day) == ^day.year)
    |> where([t], fragment("date_part('month', ?)", t.day) == ^day.month)
    |> where([t], is_nil(t.month))
    |> select([t], [t.counts, t.organization_id])
    |> Repo.all(skip_organization_id: true)
    |> monthly(day)
  end

  defp daily(results) do
    results
    |> Enum.reduce(fn result, acc ->
      Map.merge(acc, result, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end

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
          month: month,
          counts: counts,
          organization_id: organization_id
        })
    end)
  end
end
