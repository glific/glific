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

  @required_fields [:organization_id, :type, :day]
  @optional_fields [:destination_uuid, :recent_messages, :count, :month]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          type: String.t() | nil,
          day: :utc_datetime | nil,
          month: :utc_datetime | nil,
          count: integer() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "trackers" do
    field :type, :string
    field :day, :utc_datetime
    field :month, :utc_datetime
    field :count, :integer
    field :destination_uuid, Ecto.UUID
    field :recent_messages, {:array, :map}, default: []

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
  @spec upsert_tracker(map()) :: :error | Tracker.t()
  def upsert_tracker(%{flow_uuid: nil} = _attrs), do: :error

  def upsert_tracker(attrs) do
    case Repo.fetch_by(Tracker, %{uuid: attrs.uuid, flow_id: attrs.flow_id, type: attrs.type}) do
      {:ok, Tracker} ->
        update_tracker(
          Tracker,
          Map.merge(attrs, %{
            count: Tracker.count + attrs.count,
            recent_messages: Enum.take(attrs.recent_messages ++ Tracker.recent_messages, 5)
          })
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
    |> add_month(month)
    |> Repo.delete_all()
  end

  @spec add_month(Ecto.Query.t(), non_neg_integer) :: Ecto.Query.t()
  defp add_month(query, 0), do: query
  defp add_month(query, month), do:
    query
    |> where([t], t.month == ^month)
end
