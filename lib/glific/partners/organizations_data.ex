defmodule Glific.Partners.OrganizationsData do
  @moduledoc """
  Organizations are the group of users who will access the system
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  # define all the required fields for organization
  @required_fields [
    :key,
    :value,
    :organization_id
  ]

  # define all the optional fields for organization
  @optional_fields []

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          key: String.t() | nil,
          value: map() | nil,
          organization_id: non_neg_integer | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "organizations_data" do
    field :key, :string
    field :value, :map, default: %{}
    field :organization_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(OrganizationsData.t(), map()) :: Ecto.Changeset.t()
  def changeset(organizations_data, attrs) do
    organizations_data
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
