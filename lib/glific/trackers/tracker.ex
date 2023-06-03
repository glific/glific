defmodule Glific.Trackers.Tracker do
  @moduledoc """
  The tracker object
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.Partners.Organization

  @required_fields [:organization_id, :counts, :date, :period]
  @optional_fields []
  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          counts: map() | %{},
          date: Date.t() | nil,
          period: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "trackers" do
    field(:date, :date)
    field(:period, :string)
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
end
