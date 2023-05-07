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

  @required_fields [:organization_id, :counts, :day]
  @optional_fields [:destination_uuid, :month, :is_summary]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          counts: map(),
          is_summary: boolean() | false,
          day: :utc_datetime | nil,
          month: :utc_datetime | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "trackers" do
    field :type, :string
    field :day, :utc_datetime
    field :month, :utc_datetime
    field :counts, :map, default: %{}
    field :is_summary, :boolean, default: false

    belongs_to :organization, Organization

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
  @spec upsert_tracker(map(), non_neg_integer, Date.t()) :: :error | Tracker.t()
  def upsert_tracker(_counts = %{}, _organization_id, _day), do: :error

  def upsert_tracker(counts, organization_id, day) do
    day = if day == nil, do: Date.utc_today(), else: day

    attrs = %{
      counts: counts,
      organization_id: organization_id,
      day: day
    }

    case Repo.fetch_by(Tracker, %{day: day, organization_id: organization_id}) do
      {:ok, tracker} ->
        update_tracker(
          Tracker,
          Map.put(
            attrs,
            :counts,
            Map.merge(tracker.counts, counts, fn _k, v1, v2 -> v1 + v2 end))
        )

      {:error, _} ->
        create_tracker(attrs)
    end
  end

  @doc """
  Resets the tracker for a given flow in a month (optional_
  """
  @spec reset_tracker(non_neg_integer, non_neg_integer) :: any
  def reset_tracker(organization_id, month = 0) do
    Tracker
    |> where([t], t.organization_id == ^organization_id)
    |> add_month(month)
    |> Repo.delete_all()
  end

  @spec add_month(Ecto.Query.t(), non_neg_integer) :: Ecto.Query.t()
  defp add_month(query, 0), do: query
  defp add_month(query, month), do:
    query
    |> where([t], t.month == ^month)
end
