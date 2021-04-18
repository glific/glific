defmodule Glific.Partners.Saas do
  @moduledoc """
  Saas is the DB table that holds the various parameters we need to run the service.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.Partners.Organization

  # define all the required fields for saas
  @required_fields [
    :organization_id,
    :saas_phone
  ]

  # define all the optional fields for saas
  @optional_fields [:stripe_ids]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          saas_phone: String.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  @schema_prefix "global"
  schema "saas" do
    field :saas_phone, :string

    field :stripe_ids, :map

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all datat types
  """
  @spec changeset(%Glific.Partners.Saas{}, map()) :: Ecto.Changeset.t()
  def changeset(saas, attrs) do
    saas
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:name])
  end
end
