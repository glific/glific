defmodule Glific.Stats.Stat do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__
  import Ecto.Query, warn: false

  alias Glific.{Partners.Organization}

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          contacts: non_neg_integer(),
          active: non_neg_integer(),
          optin: non_neg_integer(),
          optout: non_neg_integer(),
          messages: non_neg_integer(),
          inbound: non_neg_integer(),
          outbound: non_neg_integer(),
          hsm: non_neg_integer(),
          flows_started: non_neg_integer(),
          flows_completed: non_neg_integer(),
          period: String.t() | nil,
          date: Date.t() | nil,
          hour: non_neg_integer(),
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @required_fields [
    :period,
    :date
  ]

  @optional_fields [
    :contacts,
    :active,
    :optin,
    :optout,
    :messages,
    :inbound,
    :outbound,
    :hsm,
    :flows_started,
    :flows_completed,
    :hour,
    :organization_id
  ]

  schema "stats" do
    # contact fields
    field :contacts, :integer, default: 0
    field :active, :integer, default: 0
    field :optin, :integer, default: 0
    field :optout, :integer, default: 0

    # message fields
    field :messages, :integer, default: 0
    field :inbound, :integer, default: 0
    field :outbound, :integer, default: 0
    field :hsm, :integer, default: 0

    # flow fields
    field :flows_started, :integer, default: 0
    field :flows_completed, :integer, default: 0

    # time fields
    field :period, :string, default: "hour"

    field :date, :date
    field :hour, :integer, default: 0

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Stat.t(), map()) :: Ecto.Changeset.t()
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end
end
