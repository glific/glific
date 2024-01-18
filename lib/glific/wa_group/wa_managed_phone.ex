defmodule Glific.WAGroup.WAManagedPhone do
  @moduledoc """
  Schema to manage the phone numbers for each org that are our
  peek into the happenings on a WhatsApp Group
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Partners.Organization,
    Partners.Provider,
    WAGroup.WAManagedPhone
  }

  @required_fields [
    :label,
    :phone,
    :api_token,
    :provider_id,
    :organization_id
  ]

  @optional_fields [
    :is_active
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          label: String.t() | nil,
          phone: String.t() | nil,
          is_active: boolean,
          api_token: binary | nil,
          provider_id: non_neg_integer | nil,
          provider: Provider.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime_usec | nil,
          updated_at: :utc_datetime_usec | nil
        }

  schema "wa_managed_phones" do
    field :label, :string
    field :phone, :string
    field :is_active, :boolean, default: false
    field :api_token, Glific.Encrypted.Binary

    belongs_to(:provider, Provider)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(WAManagedPhone.t(), map()) :: Ecto.Changeset.t()
  def changeset(wa_managed_phone, attrs) do
    wa_managed_phone
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
